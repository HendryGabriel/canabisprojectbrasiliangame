# Editor 2D de Biomas, Cavernas Autorais e Estúdio Criativo

## Objetivo

Evoluir as ferramentas de autoria do TRUMANCRAFT em dois módulos independentes que compartilham os mesmos formatos de assets:

1. Um editor de biomas centrado em um mapa 2D de 100x100, disponível dentro do Godot e também como ferramenta HTML standalone.
2. Um Estúdio de Estruturas com fluxo principal semelhante ao Minecraft Criativo e ferramentas avançadas em uma barra separada.

O primeiro tile continuará sendo o único bioma jogável. Cada bioma ocupa exatamente 100x100 blocos dentro da grade finita 2x2.

## Formato Terrain Tile V2

`TerrainTileData` passa para a versão 2 sem alterar a dimensão do mundo nem o save V3. O hash do asset muda, portanto saves V3 criados com outro tile continuam sendo recusados de forma explícita.

Além das grades RLE atuais, o tile armazena:

- `cave_networks`: redes autorais de cavernas.
- Cada rede contém `id`, `name`, `nodes` e `edges`.
- Cada nó contém ID estável, posição local `(x, y, z)`, tipo (`route`, `entrance` ou `chamber`) e flags opcionais.
- Nós de rota/câmara aceitam raio entre 3 e 9; nós de entrada aceitam raio entre 2 e 7.
- Cada aresta conecta dois IDs de nós e pode sobrescrever o raio/interpolação do segmento.
- `cave_overrides`: correções esparsas por voxel, separadas em escavar e preencher.

O carregador aceita Terrain Tile V1 e o converte em memória para V2. Ao exportar, grava apenas V2. A conversão preserva alturas, perfis, zonas, entradas e âncoras existentes; entradas antigas tornam-se redes unitárias até serem conectadas no editor.

## Editor de Terreno 2D no Godot

O editor passa a abrir com o mapa 2D como área principal. O preview 3D permanece acessível por uma aba ou botão, usando o mesmo tile em memória.

### Mapa

- Canvas quadrado 100x100 com zoom, pan, coordenadas sob o cursor e grade opcional.
- Modos de visualização: altura, perfil, cavernas, zonas, proteção e estruturas.
- Altura usa gradiente hipsométrico e exibe o valor Y selecionado.
- Cavernas completas usam cor por profundidade; a legenda vai da superfície até Y=-64.
- Um slider Y mostra somente túneis que intersectam a camada selecionada.
- Entradas, câmaras, bifurcações, conexões e âncoras usam ícones diferentes.

### Edição de superfície

- Os pincéis atuais continuam: elevar, baixar, suavizar, achatar, ruído, perfil, cavernas, zonas e proteção.
- Clique-arraste é um único comando de undo.
- O mapa atualiza imediatamente; o preview 3D reconstrói apenas colunas/seções afetadas.
- Alterações raras de relevo são preservadas pelo draft do Bioma 1, mas o editor não limita o autor a esse estilo.

### Edição das redes de cavernas

- Adicionar, selecionar, mover, duplicar e remover nós.
- Conectar/desconectar nós e criar bifurcações ou loops.
- Alterar X, Y, Z, raio e tipo pelo painel ou arrastando no mapa.
- Na camada Y, o mapa exibe a seção aproximada do túnel naquele nível.
- Ferramenta câmara amplia o nó sem alterar automaticamente os túneis adjacentes.
- Ferramenta de correção pinta voxels explícitos de escavação/preenchimento na camada Y.
- Operações de grafo e strokes de correção possuem undo/redo.
- Validação destaca nós fora do tile, raios inválidos, IDs duplicados, arestas órfãs e interseção com bedrock.

## Editor HTML Standalone

Adicionar `tools/terrain_editor_web/index.html`, sem servidor e sem dependências externas. O arquivo abre diretamente no navegador.

- Usa Canvas 2D para o mesmo mapa 100x100 e os mesmos modos de visualização.
- Abre arquivos `*.tterrain.json` pela File API e exporta um novo arquivo validado.
- Inclui edição de superfície, zonas, proteção, redes, nós, arestas, raio e camada Y.
- Inclui uma aba `JSON` para edição textual com validação e indicação de linha/erro.
- Importa uma imagem PNG em escala de cinza como heightmap: preto representa Y=-32 e branco representa Y=96.
- Exporta a grade de alturas como PNG para edição em programas externos.
- A importação de PNG altera somente alturas; cavernas, zonas, perfis e âncoras permanecem intactos.
- O HTML nunca sobrescreve silenciosamente o arquivo aberto; a saída usa download/exportação.
- O Godot continua sendo a autoridade final de validação ao reimportar o asset.

## Bioma 1: Planície e Duas Redes

O draft padrão do tile `(0,0)` deixa de usar o relevo montanhoso atual.

- Entre 85% e 90% das colunas ficam dentro de uma faixa local de 0 a 2 blocos.
- Elevações/depressões de 3 a 6 blocos aparecem raramente, com transições largas e suaves.
- O spawn fica plano, protegido e afastado das entradas.
- Existem duas entradas autorais com raios individuais entre 2 e 7.
- Cada entrada inicia uma rede distinta com rota principal, ramificações, becos, loops e câmaras.
- Túneis usam raios de 3 a 9; câmaras concentram os maiores raios.
- As rotas fazem zigzags e alternam descidas, pequenas subidas e trechos nivelados, mantendo progressão global até aproximadamente Y=-58.
- Uma passagem profunda e discreta conecta as duas redes.
- Nenhum segmento sai do tile 100x100 ou atravessa Y=-65.
- O ruído 3D deixa de escavar cavernas aleatórias fora das redes. A grade `cave_density` passa a modular irregularidade das paredes ao redor das rotas, sem criar sistemas independentes.

## Rasterização das Cavernas

`TerrainGenerator` recebe um rasterizador dedicado de redes.

1. Valida nós e arestas.
2. Para cada aresta, interpola centro e raio em passos menores que meio bloco.
3. Escava uma elipsoide em cada passo, com leve ruído determinístico aplicado somente à superfície do túnel.
4. Escava nós de entrada da superfície para dentro sem criar crateras além do raio configurado.
5. Amplia nós `chamber` como elipsoides autorais.
6. Aplica correções explícitas: preenchimentos vencem a rede; escavações vencem terreno e minério.
7. Estruturas continuam sendo aplicadas depois das cavernas e antes da vegetação.

O rasterizador pode calcular o AABB de cada alteração para o editor reconstruir somente seções afetadas.

## Estúdio de Estruturas no Estilo Criativo

O workspace 64x64x64 e o formato `*.tstructure.json` permanecem. A interação principal passa a ser construção em primeira pessoa com voo livre.

### Controles principais

- `WASD`, `Espaço` para subir, `Ctrl` para descer e `Shift` para acelerar mantêm o voo livre quando nenhum painel está aberto.
- `1` a `9` selecionam a hotbar.
- Clique esquerdo quebra instantaneamente.
- Clique direito coloca o bloco selecionado.
- Botão do meio copia para a hotbar o bloco sob a mira.
- Alcance criativo aumentado e outline reutilizado.
- Não há consumo de itens.

### Inventário criativo

- `E` abre/fecha uma janela central rolável.
- Mostra todos os blocos do `BlockCatalog` com ícone, nome e tooltip.
- Campo de busca filtra por ID e nome exibido.
- Categorias iniciais: construção, natureza, minério, decoração, utilidade e todos.
- Clique adiciona/seleciona o bloco na hotbar; arrastar permite reorganizar slots.
- A roda do mouse rola o catálogo sem alterar a hotbar enquanto a janela estiver aberta.

### Barra avançada separada

- `Tab` abre/fecha uma barra lateral de ferramentas avançadas.
- Contém linha, caixa, elipsoide, preencher, substituir, seleção A/B, copiar/colar, rotação, espelhamento, pincéis, pivot, fundação, ar explícito e conectores.
- A barra não ocupa o inventário criativo e não altera os controles normais enquanto fechada.
- Transformações, metadados, marcadores e voxels continuam sendo um único comando de undo/redo.
- Exportação, importação e autosave permanecem disponíveis na barra.

## Erros e Segurança de Dados

- Arquivos inválidos nunca substituem a última exportação válida.
- O editor HTML apresenta erro antes de exportar; o Godot valida novamente ao carregar.
- Redes inválidas aparecem no editor, mas não são rasterizadas silenciosamente.
- A geração retorna erros específicos por rede/nó/aresta.
- Autosaves usam V2 e mantêm arquivo de backup durante a troca atômica.

## Testes e Aceitação

- Round-trip exato de Terrain Tile V2, incluindo redes e overrides.
- Conversão V1 para V2 sem perda das grades existentes.
- Validação de raio de entrada 2–7 e túnel 3–9.
- Rejeição de IDs duplicados, arestas órfãs, bounds e bedrock.
- Rasterização contínua sem buracos entre nós e determinismo por seed/hash.
- As duas redes padrão possuem ao menos uma rota da entrada até Y<=-56 e uma conexão entre redes abaixo de Y=-45.
- O draft do Bioma 1 cumpre a distribuição de planície e mantém spawn protegido.
- Undo/redo de pincéis 2D, nós, arestas e correções por camada.
- Importação/exportação de PNG preserva a correspondência preto=-32 e branco=96.
- O editor HTML abre/exporta sem servidor.
- Inventário criativo lista todo o catálogo, busca, rolagem e hotbar funcionam.
- Construção criativa, pick block e ferramentas avançadas funcionam em bordas de seção.
- Exportar e reimportar uma estrutura produz conteúdo idêntico.
- A regressão headless existente continua limpa; o benchmark F9 permanece obrigatório no hardware-alvo.

## Ordem de Implementação

1. Terrain Tile V2 e rasterizador de redes.
2. Novo draft de planície com duas redes conectadas.
3. Canvas 2D e edição por camada no Godot.
4. Editor HTML com JSON e heightmap PNG.
5. Inventário/hotbar criativos e controles de construção.
6. Barra avançada separada.
7. Testes, documentação e benchmark manual.
