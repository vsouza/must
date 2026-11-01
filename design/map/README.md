# Base do mapa · papel em relevo

`must-relief.style.json` é o style MapLibre que reproduz `screens/Mapa.png`. Camadas de dados (metrô, rota, pinos) ficam fora do style — são adicionadas pelo app em runtime por cima.

O "relevo" é 2D: `block-shadow` é o mesmo polígono dos prédios pintado em `#121316` a 14% deslocado 2,5 px pra baixo (`fill-translate` com `viewport`), `block` é o prédio em `#F7F8FA`, e `block-highlight` é o contorno branco deslocado 0,8 px pra cima — fio de luz no topo. Em zoom < 14 os prédios somem e os polígonos de uso do solo viram quadras lisas.

Tokens:
- fundo `#E9EBEF` · quadra `#F7F8FA` · sombra `#121316` 14% · fio `#FFFFFF`
- via principal `#CFD3DB` (fita 9–16 px) · média `#DADDE3` · local `#C9CDD3` pontilhada (0.1/2.5, cap round) só a partir do z15
- parque `#E1EEE7` + sprite `dots-green` (`#5FAE7E` 45%) · água `#D9E4EF`
- nome de rua Archivo SemiBold 9.5, caps, tracking .16, `#9AA0A8`, halo da cor do fundo · bairro Archivo Bold 10, tracking .22, `#A9AEB6` · parque `#5FAE7E`
- nada de POIs, prédios 3D, relevo de terreno, ícones de transporte da base.

Em cima (runtime):
- metrô: linha 2.5 px na cor oficial, estação círculo branco borda `#121316` 1.6 + rótulo caps
- rota de hoje: trecho feito = linha `#2B7BFF` 3.5 px; trecho futuro = **contas** (círculos de 3 px a cada ~14 px)
- rota de amanhã: `#2B7BFF` 1.5 px, dasharray 1/6, 80%
- você: ponto `#2B7BFF` 15 px borda branca 2.5, halo radial 68 px 35%→0, cone de direção 22%
- pinos: ver `prompts/12-mapa-papel-em-relevo.md`
