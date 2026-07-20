# Weed Factory — Game Design Document (GDD)

> Factory builder 3D voxel temático de cultivo e processamento de cannabis.
> Engine: **Godot 4.7**. Plataforma alvo inicial: Desktop.

---

## 1. Visão geral

Você chega de mudança numa casa com quintal e, partindo de um cultivo manual
caseiro, transforma o quintal em uma fábrica automatizada. A produção acontece
em máquinas físicas, conectadas por tubos transparentes que deixam os itens
visíveis durante o transporte. O arco de progressão é **residencial → industrial**.

- **Gênero:** factory builder / automação em mundo 3D voxel + cultivo.
- **Modo:** single-player e cooperação; jogar sozinho é a mesma simulação com um jogador.
- **Câmera:** primeira pessoa, aproveitando o protótipo 3D voxel atual.
- **Mundo:** um mapa fixo, autoral e finito, dividido entre o quintal e uma cidade pequena.
- **Avatar:** personagem controlável com movimento livre em 3D, colisão e pulo.
- **Construção:** máquinas, plantações e tubos ocupam células e volumes reais da grade voxel.
- **Moeda central:** dinheiro. Camadas secundárias: metas de produção e pesquisa.
- **Clímax:** atingir o marco de maior produtor / aposentadoria milionária. A vitória
  exibe uma tela, mas mantém o sandbox do quintal disponível no mesmo mapa.

O mapa não cresce durante a partida. O jogador progride melhorando a fábrica,
desbloqueando produtos e aumentando a eficiência da logística, não comprando novos
terrenos.

---

## 2. Pilares de design (decisões travadas)

| # | Decisão | Escolha |
|---|---------|---------|
| 1 | Tipo de jogo | **Factory builder 3D voxel** com máquinas físicas |
| 2 | Engine | **Godot 4.7** |
| 3 | Câmera | **Primeira pessoa**; movimento livre, colisão e pulo |
| 4 | Transporte | **Tubos transparentes** para itens e produtos |
| 5 | Simulação de tubos | **Por células discretas**, com interpolação apenas visual |
| 6 | Economia | Dinheiro central + metas de produção + pesquisa |
| 7 | Modelo de item | `{produto, cepa}` como tags enum; sem qualidade float |
| 8 | Cepas | Distintas até o fim para flor e produtos derivados |
| 9 | Mistura | Blend por categoria: Sativa, Indica e Híbrida |
| 10 | Cultivo | `semente + água + tempo → buds`; manual → estufas automáticas |
| 11 | Água | Fluido por rede de tubos, com volume compartilhado |
| 12 | Mapa | **Fixo**, com quintal sandbox e cidade não sandbox |
| 13 | Construção | Permitida apenas no quintal e em células autorizadas |
| 14 | Energia | Global + conta de luz; brownout se faltar energia |
| 15 | Ameaça | Suspeita/calor; gestão de risco, sem combate |
| 16 | Venda | NPC comprador em cidade pequena; venda manual ou por terminal automático |
| 17 | Rota de venda | Rota fixa e protegida entre o terminal do quintal e o NPC |
| 18 | Processamento manual | Bancada/máquina física no voxel; sem craft abstrato |
| 19 | Arte | Arte 3D voxel substituível, separada da simulação |
| 20 | Rede | Lockstep determinístico, transmitindo apenas inputs |
| 21 | Autoria de máquinas | Oficina criativa com voxels de 1×, 1/2× e 1/4×; exportação para schematic |
| 22 | Coop da fábrica | Pesquisa, esquemáticos, compras e obras compartilhados por comandos ordenados |

---

## 3. Modelo de item

- Cada item é um par de enums: `{produto, cepa}` — exemplo: `{Haxixe, OG_Kush}`.
- **Sem qualidade carregada:** não existe THC float por unidade. O THC justifica
  narrativamente o preço da cepa, mas não viaja como estado do item.
- Itens com o mesmo par empilham normalmente, reduzindo o custo da simulação.
- Receitas são parametrizadas e preservam a cepa: uma receita de Haxixe serve para
  qualquer cepa compatível, sem duplicação manual.
- **Exceção — Blend:** misturar duas cepas da mesma categoria dissolve a identidade
  de cepa em uma categoria de Blend.

---

## 4. Cepas (strains)

THC define a ordem de preço e a progressão de desbloqueio. O valor é uma propriedade
da tabela de dados da cepa, não um número carregado individualmente pelo item.

| Categoria | Cepas | Papel |
|-----------|---------|---------|
| **Ruderalis** | Cannabis Ruderalis | Inicial, THC baixo, não entra em blend |
| **Sativas** | Jack Herer, Sour Diesel, Durban Poison | Tier intermediário |
| **Indicas** | Northern Lights, Granddaddy Purple, Purple Kush | Tier intermediário |
| **Híbridas** | Blue Dream, Girl Scout Cookies (GSC), OG Kush | Tier alto |

---

## 5. Cadeia de produção

### Cultivo

Ciclo: `semente + água + tempo → N buds da cepa`.

| Método | Como funciona | Tier |
|--------|---------------|------|
| **Manual** | O avatar planta, molha e colhe usando interação física | 0 |
| **Mini estufa** | Recebe semente e água por tubos, produz buds e replanta sozinha | 1 |
| **Grande estufa** | Upgrade com footprint maior e maior produção | 2 |

- Sementes são compradas no PC do quintal no início.
- Depois, um subprocesso desbloqueado produz sementes automaticamente por cepa.
- Todas as transformações continuam sendo entidades físicas no quintal.

### Processamento

Cada máquina ocupa um footprint real na grade voxel e possui portas de entrada e
saída alinhadas às faces das células. As portas são conectadas por tubos.

| Produto | Máquina | Inputs | Tamanho |
|---------|---------|--------|---------|
| **Prensado** | Bancada manual da cozinha; avatar opera | Buds | físico/manual |
| **Maconha Pura** | Máquina de um input | Buds | 1×1×1 |
| **Maconha Misturada / Blend** | Máquina de dois inputs | Duas cepas da mesma categoria | 2×2×2 |
| **Haxixe** | Máquina de múltiplos inputs | Buds | definido por blueprint |
| **Ice** | Máquina lenta | Maconha + água/gelo | 2×2×2 |
| **Canabidiol (CBD)** | Máquina | Vidro + maconha + água | 3×3×3 |
| **Baseado** | Máquina | Maconha + seda | 2×2×2 |

### Subprocessos

- **Extrator de madeira** → madeira de árvores do quintal.
- **Craft automático da seda** → seda para o Baseado.
- **Fazedor de gelo** → gelo a partir de água para o Ice.
- **Fornalha de vidro** → vidro a partir de areia/sílica para o CBD.

### Tubos transparentes

- O jogador coloca tubos apenas nas células autorizadas do quintal.
- Cada segmento é voxel-aligned e pode começar com trecho reto, curva e subida.
- Ramificações, junções e filtros entram depois do primeiro vertical slice.
- Os tubos são transparentes na apresentação; os itens aparecem como pequenas
  representações 3D movimentando-se no interior.
- A simulação usa slots discretos por célula. A posição suave do item dentro do
  tubo é interpolação visual e nunca altera o resultado do gameplay.
- Junções usam uma regra determinística de roteamento. Nenhuma ordem de Dictionary,
  física ou tempo de frame pode decidir qual item passa primeiro.
- Tubo cheio bloqueia a entrada da máquina; tubo bloqueado não destrói itens e deve
  expor visualmente o estado para o jogador.
- O tubo de venda automático termina em um **Terminal de Entrega** no limite do
  quintal. A continuação até o NPC é uma rota fixa do mapa da cidade.

### Oficina de criação de máquinas e schematics

A criação de máquinas é uma ferramenta de autoria separada do modo normal de jogo.
Ela serve para o desenvolvedor criar máquinas voxel novas e exportá-las para o
catálogo de conteúdo do jogo.

- A oficina abre um mundo criativo/superplano isolado, sem dinheiro, heat ou progressão.
- O autor constrói com voxels de tamanho normal, metade, um quarto ou um oitavo do voxel de gameplay.
- Internamente, a oficina usa uma unidade fixa de **1/8 de voxel**. Um voxel normal ocupa
  8×8×8 microvoxels; metade ocupa 4×4×4, um quarto ocupa 2×2×2 e um oitavo ocupa 1×1×1.
- Esses microvoxels formam Custom Blocks, padrões colocáveis e peças de multiblocos. Formações
  capturadas ou exportadas podem existir como itens reais durante a partida normal.
- Cada bloco-módulo é uma unidade do catálogo de blocos voxel do runtime, equivalente
  aos blocos grandes já existentes no projeto Godot. A diferença é que sua aparência
  pode ser composta internamente por microvoxels da oficina.
- O autor define a aparência e a estrutura, mas também informa footprint, pivot, colisão,
  portas de tubo, entradas, saídas, consumo de energia, rede de água e comportamento.
- A exportação gera um `StructureTemplate V4` canônico como `Custom Block`, `Multiblock` ou
  `Structure`, contendo:
  - ID e versão da máquina;
  - hash canônico do conteúdo;
  - lista de cada bloco-módulo/peça macro e sua coordenada local na grade da máquina;
  - referência ao conjunto de microvoxels que forma cada bloco-módulo;
  - rotação, espelhamento permitido e pivot;
  - footprint e envelope de construção;
  - portas de tubo/fluido/energia;
  - ID da receita ou comportamento simulado;
  - lista de peças vendáveis e requisitos de pesquisa.
- A exportação rejeita voxels desconhecidos, peças fora do envelope, portas inválidas,
  IDs duplicados ou dados que não possam ser serializados de forma determinística.

### Como o jogador adquire e constrói uma schematic

1. O desenvolvedor exporta a máquina no modo de criação e adiciona a schematic ao catálogo.
2. Na partida, o jogador encontra a schematic na **Mesa de Pesquisas**.
3. O jogador inicia e conclui a pesquisa; o conhecimento é desbloqueado para a fábrica.
4. Com a schematic aprendida, o jogador seleciona o ghost e posiciona a máquina em
   qualquer lugar válido do quintal, antes de comprar os materiais.
5. O ghost mostra footprint, pivot, portas, altura, colisões e cada posição que será
   preenchida. A simulação valida a área, mas ainda não consome peças.
6. Ao confirmar uma montagem, a peça-âncora cria uma receita espacial com ghosts exatos:
   cada entrada aponta para `asset_id` ou `voxel_id`, coordenada local e rotação da peça.
7. O NPC comerciante da cidade passa a vender cada bloco-módulo grande da schematic
   aprendida. Cada bloco vendido já contém os microvoxels construídos na autoria.
8. O jogador compra os blocos-módulo, leva-os ao quintal e os instala no canteiro
   seguindo o manifesto. A obra só ativa o comportamento quando todas as peças obrigatórias,
   portas e conexões estiverem completas.

No jogo normal, o jogador pode posicionar Custom Blocks e padrões de microvoxels exportados.
Ele também posiciona o projeto inteiro ou monta as peças autorizadas pelo manifesto. O sistema
de tubos pode receber materiais para a obra em uma etapa futura; o primeiro fluxo usa
inventário e colocação manual para manter o escopo controlado.

---

## 6. Economia e venda

### Compras

- O PC fica no quintal e vende sementes, materiais iniciais, tubos e upgrades.
- Compras são instantâneas, consomem dinheiro e respeitam os desbloqueios.
- Não existe compra de lote, expansão de terreno ou compra de novas áreas.

### Comerciante e peças de máquina

- O mesmo NPC da cidade compra os produtos ilegais e vende as peças das máquinas
  aprendidas na Mesa de Pesquisas. Não é necessário criar um segundo NPC para a loja.
- Antes da pesquisa, o catálogo da schematic fica bloqueado e as peças não são vendidas.
- Depois da pesquisa, cada bloco-módulo aparece com `machine_block_id`, preço, quantidade
  e referência à schematic que o utiliza.
- O `machine_block_id` é o item comprado, empilhado, transportado e instalado; não há
  preço ou estoque separado para os microvoxels internos.
- Comprar um bloco-módulo não o coloca automaticamente na máquina. Ele entra no
  inventário ou no armazenamento disponível e precisa ser instalado no canteiro correto.
- O dinheiro da operação, o conhecimento pesquisado, o catálogo do comerciante e os
  canteiros são estado compartilhado da fábrica no coop.

### Venda manual

- O avatar coleta o produto e carrega uma quantidade limitada até o NPC da cidade.
- A interação com o NPC confirma a venda e transforma o estoque em dinheiro.
- A cidade é pequena e tem apenas o comprador, sua área de interação e a rota de
  entrega fixa.

### Venda automática

- O jogador conecta a saída da fábrica a um Terminal de Entrega no limite do quintal.
- O terminal aceita somente produtos vendáveis e envia lotes pela rota protegida da
  cidade até o NPC.
- O NPC paga conforme os lotes chegam, permitindo uma fábrica realmente automática.
- O jogador não constrói, remove ou modifica tubos na cidade.

### Valor e custos

- Flor crua tem preço por cepa; produtos processados valem mais.
- A conta de luz drena dinheiro continuamente e escala com o consumo.
- Metas de produção destravam tiers e tecnologia.
- Pesquisa oferece melhorias de eficiência, capacidade, controle de risco e schematics.

---

## 7. Energia

- Modelo global: geração total contra consumo total, sem postes ou área de cobertura.
- No início, a casa fornece energia e cobra conta de luz.
- Se consumo > geração, ocorre **brownout** e as máquinas/tubos trabalham mais devagar.
- Mais tarde, o jogador constrói geração própria: solar e biomassa de restos de
  cannabis ou madeira, reduzindo a conta.

---

## 8. Suspeita / Calor

- Produzir e vender aumenta suspeita por cheiro, movimento e visibilidade.
- O jogador gerencia risco com dinheiro, filtro de carvão, muros, cercas e fachada legal.
- Ao estourar, ocorre batida policial com multa e confisco de dinheiro ou estoque.
- Não existe combate ou shooter.
- A venda automática aumenta eficiência, mas também pode aumentar o calor por volume.

---

## 9. Arquitetura técnica

### Simulação

- A simulação é própria, em passo fixo, usando inteiros ou ponto fixo.
- Estado autoritativo não lê relógio, delta de frame, transform, física do Godot,
  RNG global ou ordem não determinística de coleções.
- A grade voxel, as máquinas, os tubos, os itens, a energia, o dinheiro e o calor
  pertencem ao estado da simulação.
- Cada entidade possui ID estável. Iterações são ordenadas explicitamente por ID ou
  por coordenada determinística.
- O hash do estado é calculado a cada tick para validar o lockstep.

### Renderização

- Godot 4.7 apresenta o estado da simulação em 3D voxel.
- O renderizador interpola avatar, itens e efeitos entre ticks.
- Tubos transparentes e itens dentro deles são visuais; o conteúdo autoritativo
  continua sendo o slot discreto do tubo.
- Sprites, meshes, materiais e efeitos ficam separados da lógica de produção.

### Autoria, microvoxels e schematics

- A oficina de criação usa coordenadas inteiras em oitavos de voxel; não usa float para
  definir a posição de um microvoxel ou de um bloco-módulo.
- `StructureTemplate V4` tem serialização canônica, versão e hash. O mesmo arquivo precisa gerar
  o mesmo hash em todas as máquinas e todos os peers.
- O catálogo de runtime vende e empilha `machine_block_id` como uma unidade. Cada
  bloco-módulo referencia o conjunto de microvoxels usado para desenhá-lo.
- O renderizador pode mostrar o ghost com transparência e os microvoxels com suavização,
  mas o footprint, o manifesto, as portas e as regras de montagem são autoritativos na sim.
- O asset não executa código arbitrário. Seu `utility_id` aponta para um ID de
  máquina/receita já registrado e validado no catálogo.

### Cooperação

- Single-player e coop rodam a mesma simulação.
- A rede transmite comandos ordenados, como construir tubo em uma célula, operar a
  bancada, pesquisar uma schematic, comprar um bloco-módulo ou instalar uma peça no canteiro.
- O hash da schematic, a pesquisa concluída e o manifesto do canteiro precisam existir
  de forma idêntica em todos os peers antes da obra começar.
- Pesquisas, catálogo do comerciante e canteiros pertencem à fábrica. Jogadores podem
  operar a mesma obra, mas a ordem dos comandos resolve compras e colocações conflitantes.
- Os clientes não transmitem posição de item nem estado final; cada peer recalcula.
- Invariante: mesmos inputs ordenados → mesmo estado e mesmo hash em todo tick.

---

## 10. Avatar

- Movimento livre em primeira pessoa, com gravidade, colisão e pulo.
- O avatar anda pelo quintal e pela cidade, mas apenas o quintal aceita construção.
- O inventário é pequeno e permite carregar itens até as máquinas ou até o NPC.
- Não existe craft abstrato no inventário: processos são feitos em bancadas e
  máquinas físicas.
- O modo de colocação de schematic cria um ghost orientado por grid e mostra o manifesto
  de peças antes de qualquer compra.
- A interação manual tem alcance, tempo e feedback visual definidos pela simulação.

---

## 11. Mundo e mapa fixo

O jogo usa um único mapa voxel autoral, preparado antes da partida e carregado com
uma seed fixa. O mapa pode ter detalhes procedurais dentro dos limites definidos,
mas seus limites e suas regiões não mudam durante a partida.

### Região A — Quintal da casa

- Área sandbox principal.
- Permite construção e remoção de máquinas, tubos e estruturas autorizadas.
- Contém a casa, PC, bancada, áreas de cultivo e recursos iniciais.
- Contém água, árvores e areia suficientes para o início da progressão.
- O jogador organiza toda a fábrica nessa região.

### Região B — Cidade pequena

- Área fixa, pequena e não sandbox.
- Não permite colocar ou remover blocos, máquinas, plantações ou tubos.
- Contém apenas o caminho de acesso, o NPC comprador e a rota fixa de entrega.
- Funciona como destino de venda, não como segundo espaço de construção.
- A rota fixa termina no mesmo NPC usado pela venda manual.

### Fronteira entre regiões

- A fronteira é uma regra de gameplay, não apenas uma parede visual.
- O Terminal de Entrega fica no lado do quintal.
- A rota protegida começa depois do terminal e pertence ao mapa da cidade.
- Tentativas de construção na cidade são rejeitadas pela simulação e pelo modo de
  colocação visual.

---

## 12. Escopo deixado para depois (não objetivos do v1)

- Transporte pixel-a-pixel contínuo: o transporte usa tubos por células.
- Pressão de fluido por segmento: o fluido usa volume compartilhado por rede.
- Compra de lotes e expansão do terreno: o mapa é fixo.
- Mapa procedural infinito ou novos biomas carregados durante a partida.
- Construção livre na cidade ou múltiplos distritos comerciais.
- Veículos autônomos de entrega: a primeira automação usa terminal e rota fixa.
- Edição unitária da grade `8×8×8` fora do Estúdio: no mapa normal o jogador coloca padrões,
  Custom Blocks e peças exportadas como unidades de inventário.
- Schematics com comportamento arbitrário ou scripts exportados pelo usuário: o catálogo
  aceita apenas comportamentos registrados e determinísticos.
- Postes e fios com área de cobertura: a energia é global.
- Combate físico com a polícia.
- Qualidade/THC float por unidade.
- Luz e nutrientes detalhados no cultivo; entram apenas como upgrades futuros.

---

## 13. Próximos passos

1. Fixar o mapa voxel autoral com as regiões `QUINTAL` e `CIDADE`.
2. Implementar permissões de construção por região e o Terminal de Entrega.
3. Criar o núcleo determinístico em passo fixo com hash por tick.
4. Criar a oficina criativa, a grade de microvoxels e a exportação de `SchematicData`.
5. Implementar item, inventário e uma fila de slots de tubo.
6. Fazer tubos transparentes retos funcionarem visualmente com um item dentro.
7. Criar uma máquina simples, a saída de produto e a rota fixa até o NPC.
8. Implementar cultivo manual como primeiro loop jogável.
9. Implementar Mesa de Pesquisas, schematic aprendida e catálogo de blocos-módulo do NPC.
10. Implementar ghost, manifesto de construção e instalação exata dos blocos-módulo.
11. Implementar venda manual, venda automática e dinheiro.
12. Adicionar mini estufa e o primeiro ciclo completo de automação.
13. Adicionar as cadeias de processamento e as redes de água.
14. Adicionar energia, brownout, suspeita, metas e pesquisa avançada.
15. Adicionar salvamento determinístico e regressões de lockstep.
16. Integrar coop da fábrica: pesquisa, compras, ghost e obras simultâneas.
17. Integrar arte voxel fornecida pelo desenvolvedor, UI e balanceamento.
