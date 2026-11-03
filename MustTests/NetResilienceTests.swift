import Foundation
import SwiftData
import Synchronization
import Testing
@testable import Must

/// Prompt 18 · A.4: offline na hora, retry só em GET transitório, disjuntor, dedupe e fila de saída.
/// Sem rede real: `NetStub` (URLProtocol) responde por host; cada teste usa um host próprio.
final class NetStub: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        case ok(Data)
        case status(Int, retryAfter: String? = nil)
        case error(URLError.Code)
    }

    struct Script: Sendable {
        var replies: [Reply]
        var delay: Double = 0
        var hits = 0
    }

    static let scripts = Mutex<[String: Script]>([:])
    /// Flag `allowsConstrainedNetworkAccess` que chegou em cada host.
    static let constrainedFlags = Mutex<[String: Bool]>([:])

    static func register(_ host: String, _ replies: [Reply], delay: Double = 0) {
        scripts.withLock { $0[host] = Script(replies: replies, delay: delay) }
    }

    static func hits(_ host: String) -> Int {
        scripts.withLock { $0[host]?.hits ?? 0 }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host()?.hasSuffix(".netstub.test") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        let url = request.url ?? URL(string: "https://\(host)/")!
        Self.constrainedFlags.withLock { $0[host] = request.allowsConstrainedNetworkAccess }
        let (reply, delay): (Reply, Double) = Self.scripts.withLock { all in
            guard var script = all[host], !script.replies.isEmpty else { return (.error(.cannotFindHost), 0) }
            let index = min(script.hits, script.replies.count - 1)
            script.hits += 1
            all[host] = script
            return (script.replies[index], script.delay)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            switch reply {
            case .ok(let data):
                respond(url, code: 200, data: data, headers: [:])
            case .status(let code, let retryAfter):
                respond(url, code: code, data: Data("{}".utf8), headers: retryAfter.map { ["Retry-After": $0] } ?? [:])
            case .error(let code):
                client?.urlProtocol(self, didFailWithError: URLError(code))
            }
        }
    }

    private func respond(_ url: URL, code: Int, data: Data, headers: [String: String]) {
        let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Pausas gravadas (sem dormir de verdade) e HTTP com a sessão do stub.
private final class PauseLog: @unchecked Sendable {
    let durations = Mutex<[Duration]>([])
}

private func stubbedHTTP(host: String, retries: Int = 2, breaker: CircuitBreaker? = CircuitBreaker(),
                         inFlight: InFlight? = nil, connectivity: Connectivity.Status = .online,
                         log: PauseLog = PauseLog()) -> HTTP {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [NetStub.self]
    return HTTP(session: URLSession(configuration: config), retries: retries, breaker: breaker, inFlight: inFlight,
                connectivity: { connectivity },
                pause: { duration in log.durations.withLock { $0.append(duration) } },
                jitter: { 1 })
}

private func url(_ host: String, _ path: String = "/x") -> URL {
    URL(string: "https://\(host)\(path)")!
}

struct HTTPResilienceTests {
    @Test func meteredHostsAreNeverRetried() {
        #expect(AppNetwork.isMetered("places.googleapis.com"))
        #expect(AppNetwork.isMetered("routes.googleapis.com"))
        #expect(AppNetwork.isMetered("aerodatabox.p.rapidapi.com"))
        #expect(AppNetwork.isMetered("api.anthropic.com"))
        #expect(!AppNetwork.isMetered("api.open-meteo.com"))
        #expect(!AppNetwork.isMetered("commons.wikimedia.org"))
    }

    @Test func offlineFailsAtOnceWithoutTouchingTheNetwork() async {
        let host = "offline-\(UUID().uuidString.prefix(6)).netstub.test"
        NetStub.register(host, [.ok(Data("{}".utf8))])
        let http = stubbedHTTP(host: host, connectivity: .offline)
        let started = ContinuousClock.now
        await #expect(throws: ServiceError.offline) {
            _ = try await http.get(url(host), service: "t")
        }
        #expect(ContinuousClock.now - started < .milliseconds(500))
        #expect(NetStub.hits(host) == 0)
    }

    @Test func getRetriesTransientErrorsAtMostTwice() async {
        let host = "retry-\(UUID().uuidString.prefix(6)).netstub.test"
        NetStub.register(host, [.status(503)])
        let http = stubbedHTTP(host: host)
        await #expect(throws: ServiceError.http(503, "{}")) {
            _ = try await http.get(url(host), service: "t")
        }
        // 1 tentativa + 2 repetições, nem uma a mais.
        #expect(NetStub.hits(host) == 3)
    }

    @Test func getRecoversWhenALaterAttemptWorks() async throws {
        let host = "recover-\(UUID().uuidString.prefix(6)).netstub.test"
        NetStub.register(host, [.error(.timedOut), .ok(Data("certo".utf8))])
        let http = stubbedHTTP(host: host)
        let data = try await http.get(url(host), service: "t")
        #expect(String(decoding: data, as: UTF8.self) == "certo")
        #expect(NetStub.hits(host) == 2)
    }

    @Test func postNeverRetries() async {
        let host = "post-\(UUID().uuidString.prefix(6)).netstub.test"
        NetStub.register(host, [.error(.timedOut)])
        let http = stubbedHTTP(host: host)
        await #expect(throws: URLError.self) {
            _ = try await http.post(url(host), json: ["a": 1], service: "t")
        }
        #expect(NetStub.hits(host) == 1)

        let host503 = "post503-\(UUID().uuidString.prefix(6)).netstub.test"
        NetStub.register(host503, [.status(503)])
        await #expect(throws: ServiceError.http(503, "{}")) {
            _ = try await stubbedHTTP(host: host503).post(url(host503), json: [:], service: "t")
        }
        #expect(NetStub.hits(host503) == 1)
    }

    @Test func clientErrorsAreNotRetried() async {
        let host = "404-\(UUID().uuidString.prefix(6)).netstub.test"
        NetStub.register(host, [.status(404)])
        let http = stubbedHTTP(host: host)
        await #expect(throws: ServiceError.http(404, "{}")) {
            _ = try await http.get(url(host), service: "t")
        }
        #expect(NetStub.hits(host) == 1)
    }

    @Test func retryAfterShortIsHonouredOnRateLimit() async throws {
        let host = "429-\(UUID().uuidString.prefix(6)).netstub.test"
        NetStub.register(host, [.status(429, retryAfter: "2"), .ok(Data("{}".utf8))])
        let log = PauseLog()
        let http = stubbedHTTP(host: host, log: log)
        _ = try await http.get(url(host), service: "t")
        #expect(log.durations.withLock { $0 } == [.seconds(2)])
    }

    @Test func breakerOpensAfterThreeFailuresAndClosesAfterCooldown() async throws {
        let host = "breaker-\(UUID().uuidString.prefix(6)).netstub.test"
        NetStub.register(host, [.status(503), .status(503), .status(503), .ok(Data("{}".utf8))])
        let clock = Mutex(Date(timeIntervalSince1970: 1_000_000))
        let breaker = CircuitBreaker(now: { clock.withLock { $0 } })
        let http = stubbedHTTP(host: host, retries: 0, breaker: breaker)
        for _ in 0..<3 {
            await #expect(throws: ServiceError.http(503, "{}")) { _ = try await http.get(url(host), service: "svc") }
        }
        // Aberto: falha rápido, sem tocar a rede.
        await #expect(throws: ServiceError.circuitOpen("svc")) { _ = try await http.get(url(host), service: "svc") }
        #expect(NetStub.hits(host) == 3)
        #expect(await breaker.label("svc") == "aberto")

        // 2 min depois: meia-abertura deixa uma tentativa passar, que dá certo e fecha.
        clock.withLock { $0 = $0.addingTimeInterval(121) }
        _ = try await http.get(url(host), service: "svc")
        #expect(NetStub.hits(host) == 4)
        #expect(await breaker.label("svc") == "fechado")
    }

    @Test func breakerIsPerService() async {
        let host = "perservice-\(UUID().uuidString.prefix(6)).netstub.test"
        NetStub.register(host, [.status(503)])
        let breaker = CircuitBreaker()
        let http = stubbedHTTP(host: host, retries: 0, breaker: breaker)
        for _ in 0..<3 {
            await #expect(throws: ServiceError.http(503, "{}")) { _ = try await http.get(url(host), service: "a") }
        }
        // Outro serviço continua indo pra rede.
        await #expect(throws: ServiceError.http(503, "{}")) { _ = try await http.get(url(host), service: "b") }
        #expect(NetStub.hits(host) == 4)
    }

    @Test func simultaneousGetsShareOneRequest() async throws {
        let host = "dedupe-\(UUID().uuidString.prefix(6)).netstub.test"
        NetStub.register(host, [.ok(Data("um".utf8))], delay: 0.3)
        let http = stubbedHTTP(host: host, inFlight: InFlight())
        async let first = http.get(url(host, "/mesma"), service: "t")
        async let second = http.get(url(host, "/mesma"), service: "t")
        let (a, b) = try await (first, second)
        #expect(a == b)
        #expect(NetStub.hits(host) == 1)
    }

    @Test func differentGetsAreNotJoined() async throws {
        let host = "nodedupe-\(UUID().uuidString.prefix(6)).netstub.test"
        NetStub.register(host, [.ok(Data("x".utf8))], delay: 0.2)
        let http = stubbedHTTP(host: host, inFlight: InFlight())
        async let first = http.get(url(host, "/a"), service: "t")
        async let second = http.get(url(host, "/b"), service: "t")
        _ = try await (first, second)
        #expect(NetStub.hits(host) == 2)
    }

    @Test func prefetchRequestsRefuseConstrainedNetworks() async throws {
        // Pré-download não gasta dado do Modo de Pouco Dados; pedido de tela, sim.
        let prefetchHost = "prefetch-\(UUID().uuidString.prefix(6)).netstub.test"
        NetStub.register(prefetchHost, [.ok(Data())])
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NetStub.self]
        let prefetch = HTTP(session: URLSession(configuration: config), kind: .prefetch, breaker: nil, inFlight: nil,
                             connectivity: { .online })
        _ = try await prefetch.get(url(prefetchHost), service: "t")
        #expect(NetStub.constrainedFlags.withLock { $0[prefetchHost] } == false)

        let screenHost = "screen-\(UUID().uuidString.prefix(6)).netstub.test"
        NetStub.register(screenHost, [.ok(Data())])
        _ = try await stubbedHTTP(host: screenHost).get(url(screenHost), service: "t")
        #expect(NetStub.constrainedFlags.withLock { $0[screenHost] } == true)
    }
}

@MainActor
@Suite struct OutboxTests {
    final class Calls: @unchecked Sendable {
        let count = Mutex(0)
    }

    struct CountingSource: FlightStatusProviding {
        let calls: Calls
        var error: ServiceError?

        func report(number: String, departureIATA: String, day: String) async throws -> FlightStatusReport? {
            calls.count.withLock { $0 += 1 }
            if let error { throw error }
            return FlightStatusReport(status: .onTime, departs: nil, arrives: nil, terminal: "3", gate: "B12")
        }
    }

    static func container() throws -> ModelContainer {
        try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    static func iso(_ text: String) -> Date { BoardDates.parseDateTime(text)! }

    /// GRU → DOH → HND, 14–15 nov (horário local de cada aeroporto).
    static func trip() -> [FlightSegment] {
        [FlightSegment(number: "LA 8084", from: "GRU", to: "DOH", departs: iso("2026-11-14T23:55:00-03:00"),
                       arrives: iso("2026-11-15T06:20:00+03:00")),
         FlightSegment(number: "QR 0758", from: "DOH", to: "HND", departs: iso("2026-11-15T02:30:00+03:00"),
                       arrives: iso("2026-11-15T19:00:00+09:00"))]
    }

    nonisolated static let link = "https://www.instagram.com/p/outbox-teste/"

    @Test func linkReadOfflineIsQueuedAndReadWhenBackOnline() async throws {
        let context = ModelContext(try Self.container())
        Outbox.enqueue(.readLink, ref: Self.link, context: context)
        Outbox.enqueue(.readLink, ref: Self.link, context: context)
        #expect(Outbox.waitingCount(context) == 1)

        // Sem rede: nada sai, nada muda.
        let offline = await Outbox.drain(context: context, region: .jp, isOnline: { false }, flightSource: nil,
                                         fetchCaption: { _ in Caption(source: .instagram, title: nil, text: "x", url: nil) })
        #expect(offline == 0)
        #expect(Outbox.waitingCount(context) == 1)

        // De volta: lê o link e guarda a legenda pro Adicionar.
        let done = await Outbox.drain(context: context, region: .jp, isOnline: { true }, flightSource: nil,
                                      fetchCaption: { ref in
                                          #expect(ref == Self.link)
                                          return Caption(source: .instagram, title: "Post", text: "Koffee Mamé, Nakameguro", url: nil)
                                      })
        #expect(done == 1)
        #expect(Outbox.waitingCount(context) == 0)
        let ready = Outbox.readyCaption(for: Self.link, context: context)
        #expect(ready?.caption.text == "Koffee Mamé, Nakameguro")
        #expect(ready?.caption.source == .instagram)
    }

    @Test func linkQueueGivesUpAfterMaxAttemptsButNotWhenOffline() async throws {
        let context = ModelContext(try Self.container())
        let item = Outbox.enqueue(.readLink, ref: Self.link, context: context, now: Date(timeIntervalSince1970: 0))
        let failing: @Sendable (String) async throws -> Caption = { _ in throw URLError(.timedOut) }
        var now = Date(timeIntervalSince1970: 0)
        // Offline não conta tentativa.
        await Outbox.drain(context: context, region: .jp, now: now, isOnline: { false }, flightSource: nil, fetchCaption: failing)
        #expect(item.attempts == 0)
        for _ in 0..<Outbox.maxAttempts {
            now = item.nextTry.addingTimeInterval(1)
            await Outbox.drain(context: context, region: .jp, now: now, isOnline: { true }, flightSource: nil, fetchCaption: failing)
        }
        #expect(item.done)
        #expect(item.attempts == Outbox.maxAttempts)
    }

    @Test func offlineFlightRefreshQueuesWithoutMarkingTheLeg() async throws {
        let context = ModelContext(try Self.container())
        let flight = Flight(pnr: "X", legs: Self.trip(), checklist: [])
        context.insert(flight)
        let now = Self.iso("2026-11-14T12:00:00-03:00")
        let calls = Calls()
        let count = await FlightStatusUpdater.refresh(flight, context: context, now: now, region: .jp,
                                                      source: CountingSource(calls: calls, error: .offline))
        #expect(count == 0)
        #expect(flight.legs.allSatisfy { $0.statusFetchedAt == nil })
        #expect(Outbox.waitingCount(context) == 1)
        #expect(Outbox.undone(context).first?.outboxKind == .flightStatus)
    }

    @Test func flightOutboxRespectsFlightPolicy() async throws {
        let context = ModelContext(try Self.container())
        let flight = Flight(pnr: "X", legs: Self.trip(), checklist: [])
        context.insert(flight)
        Outbox.enqueue(.flightStatus, ref: flight.id, context: context)

        // Três dias antes: fora da janela de 24 h. A fila não gasta consulta e termina o item.
        let early = Self.iso("2026-11-11T12:00:00-03:00")
        let calls = Calls()
        let source = CountingSource(calls: calls)
        await Outbox.drain(context: context, region: .jp, now: early, isOnline: { true }, flightSource: source,
                           fetchCaption: { _ in throw URLError(.badURL) })
        #expect(calls.count.withLock { $0 } == 0)
        #expect(Outbox.waitingCount(context) == 0)
    }

    @Test func flightOutboxQueriesOnlyDueLegsInsideTheWindow() async throws {
        let context = ModelContext(try Self.container())
        let flight = Flight(pnr: "X", legs: Self.trip(), checklist: [])
        context.insert(flight)
        Outbox.enqueue(.flightStatus, ref: flight.id, context: context)

        // 14 nov, 12:00 em GRU: o trecho da noite (23:55) está na janela; o de Doha ainda não é consultado de novo
        // depois da primeira passada (cache de 30 min vale).
        let inside = Self.iso("2026-11-14T12:00:00-03:00")
        let calls = Calls()
        let source = CountingSource(calls: calls)
        await Outbox.drain(context: context, region: .jp, now: inside, isOnline: { true }, flightSource: source,
                           fetchCaption: { _ in throw URLError(.badURL) })
        let first = calls.count.withLock { $0 }
        #expect(first == 2)
        #expect(Outbox.waitingCount(context) == 0)
        #expect(flight.legs.allSatisfy { $0.statusFetchedAt == inside })

        // Mesmo minuto de novo (sem item na fila): a política segura a consulta.
        Outbox.enqueue(.flightStatus, ref: flight.id, context: context, now: inside)
        await Outbox.drain(context: context, region: .jp, now: inside.addingTimeInterval(60), isOnline: { true },
                           flightSource: source, fetchCaption: { _ in throw URLError(.badURL) })
        #expect(calls.count.withLock { $0 } == first)
    }
}
