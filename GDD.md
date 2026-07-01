# Weed Factory — Game Design Document (GDD)

> Factory builder (estilo Factorio) temático de cultivo e processamento de cannabis.
> Engine: **Godot 4.6**. Plataforma alvo inicial: Desktop.

---

## 1. Visão geral

Você chega de mudança numa casa com quintal e, partindo de um cultivo manual
caseiro, expande o terreno e automatiza tudo até virar uma **fábrica 100%
automática** que imprime dinheiro. Arco de progressão: **residencial → industrial**.

- **Gênero:** factory builder / automação (Factorio raiz) + cultivo (Stardew Valley).
- **Modo:** **single-player e coop** (o mesmo jogo suporta jogar sozinho ou em cooperação).
- **Câmera e gráficos:** top-down 2D, visual e câmera **bem parecidos com Stardew Valley
  e Factorio** (perspectiva de cima, mundo em tiles, máquinas/esteiras alinhadas ao grid).
  **Não é pixelart** — arte com traço/ilustração mais limpo, não em pixels.
- **Avatar:** sim — personagem controlável (Factorio clássico), movimento **livre em 8 direções**.
- **Moeda central:** dinheiro. Camadas secundárias: metas de produção e pesquisa.
- **Clímax:** marco de vitória (virar o maior produtor / se aposentar milionário) que
  **não tranca** — dispara tela de vitória e libera sandbox infinito.

---

## 2. Pilares de design (decisões travadas)

| # | Decisão | Escolha |
|---|---------|---------|
| 1 | Tipo de jogo | **Factorio raiz** — esteiras físicas, itens viajam no grid |
| 2 | Engine | **Godot 4.6** (apenas renderizador — ver §9) |
| 3 | Avatar | **Sim**, movimento livre em 8 direções |
| 4 | Simulação de esteira | **Por células (discreto)** com interpolação visual |
| 5 | Economia | **Dinheiro central** + metas de produção (estilo Space Elevator) + pesquisa |
| 6 | Modelo de item | `{produto, cepa}` como **tags enum** (sem qualidade float). Empilha por par |
| 7 | Cepas | **Distintas até o fim** (flor crua e produtos por cepa) |
| 8 | Mistura | **Blend por categoria** — Sativa/Indica/Híbrida (3 produtos genéricos) |
| 9 | Cultivo | `semente + água + tempo → buds`. Manual (Stardew) → estufas automáticas |
| 10 | Água | **Fluido real** com canos |
| 11 | Simulação de fluido | **Volume compartilhado por rede** (sem pressão por segmento) |
| 12 | Mapa | **Terreno finito expansível** comprando lotes |
| 13 | Energia | **Global + conta de luz** (brownout se faltar; gerar própria depois) |
| 14 | Ameaça | **Suspeita/calor** (gestão de risco, sem combate) |
| 15 | Venda | **Doca física** (traficante no beco) alimentada por esteira |
| 16 | Final | **Marco de vitória que não tranca** |
| 17 | Processamento manual | **Tudo é bancada/máquina física no grid** (sem craft-na-mão abstrato) |
| 18 | Arte | Sprites **fornecidos pelo desenvolvedor**; **não é pixelart**; estilo Stardew/Factorio; lógica separada do visual |
| 19 | Modo | **Single-player e coop** |
| 20 | Rede | **Lockstep determinístico** (input-only) |

---

## 3. Modelo de item

- Cada item é um par de enums: `{produto, cepa}` — ex. `{Haxixe, OG_Kush}`.
- **Sem qualidade carregada** (sem THC float por unidade). O THC é só a justificativa
  narrativa do preço de cada cepa, não um stat que viaja com o item.
- Itens com o mesmo par **empilham** normalmente (essencial pra compressão de esteira).
- Receitas são **parametrizadas e preservam a cepa**: existe **uma** receita de Haxixe
  ("bud da cepa X → haxixe da cepa X"), não 9 receitas escritas à mão.
- **Exceção — Blend:** misturar 2 cepas da mesma categoria dissolve a identidade de
  cepa em **categoria** (ver §5).

---

## 4. Cepas (strains)

THC define a ordem de preço (baixo → alto) e a progressão de desbloqueio.

| Categoria | Cepas | Papel |
|-----------|-------|-------|
| **Ruderalis** | Cannabis Ruderalis | Inicial, THC baixo. Starter. Não entra em blend (categoria solo) |
| **Sativas** | Jack Herer, Sour Diesel, Durban Poison | Tier intermediário |
| **Indicas** | Northern Lights, Granddaddy Purple, Purple Kush | Tier intermediário |
| **Híbridas** | Blue Dream, Girl Scout Cookies (GSC), OG Kush | Tier alto |

---

## 5. Cadeia de produção

### Cultivo (fonte de buds)
Ciclo: `semente + água + tempo → N buds da cepa`.

| Método | Como funciona | Tier |
|--------|---------------|------|
| **Manual** | Estilo Stardew: avatar **planta → molha → colhe** à mão. Ciclos **curtos** (sentir progressão). Grátis, lento, exige presença | 0 |
| **Mini estufa** | Automática, I/O por esteira (entra semente+água, sai bud), replanta sozinha | 1 |
| **Grande estufa** | Upgrade da mini: mesmo comportamento, **footprint maior, mais output** | 2 |

- **Sementes:** compradas no **PC** no início; depois desbloqueia subprocesso que
  **auto-produz semente** a partir da própria cepa (bootstrap → infinito).

### Processamento
Cada máquina ocupa footprint real no grid com pontos de I/O posicionados.

| Produto | Máquina | Inputs | Tamanho |
|---------|---------|--------|---------|
| **Prensado** | Bancada manual (cozinha) — avatar opera | Buds | manual |
| **Maconha Pura** | Máquina 1 input | Buds | 1×1 |
| **Maconha Misturada → Blend** | Máquina 2 inputs | 2 cepas da **mesma categoria** → Blend Sativa/Indica/Híbrida | 2×2 |
| **Haxixe** | Máquina múltiplos inputs | Buds (múltiplos) | — |
| **Ice** | Máquina **lenta** | Maconha + Água/Gelo | 2×2 |
| **Canabidiol (CBD)** | Máquina | Vidro + Maconha + Água | 3×3 |
| **Baseado** | Máquina | Maconha + Seda | 2×2 |

### Subprocessos (cadeias de apoio)
- **Extrator de madeira** → madeira (de árvores no terreno).
- **Craft automático da seda** → seda (input do Baseado).
- **Fazedor de gelos** → gelo (de água; input do Ice).
- **Fornalha de vidro** → vidro (de areia/sílica; input do CBD).

---

## 6. Economia e venda

- **Comprar (entrada):** menu do **PC** — sementes, máquinas, lotes de terra, upgrades.
  Instantâneo, gasta dinheiro.
- **Vender (saída):** **doca física** = **traficante no beco escuro ao lado da casa**.
  A esteira despeja o produto acabado nele → dinheiro pinga ao longo do tempo.
  Cru no manual (avatar leva na mão) → automático no fim (esteira alimenta sozinha).
- **Flor crua** vende com preço **por cepa** (OG Kush > Ruderalis). Produtos processados
  valem mais.
- **Conta de luz:** dreno constante de dinheiro que escala com o consumo das máquinas.
- **Metas de produção:** entregas-marco (estilo Space Elevator) destravam tiers/tecnologia.
- **Pesquisa:** camada secundária de desbloqueio/refino.

---

## 7. Energia

- Modelo **global**: geração total vs consumo total. **Sem postes / sem área de cobertura**.
- Início: plugado na **rede da casa**, paga **conta de luz**.
- Se consumo > geração → **brownout** (tudo desacelera).
- Progressão: construir **geração própria** (solar, biomassa de resto de cannabis/madeira)
  pra cortar a conta.

---

## 8. Suspeita / Calor (a "ameaça")

- Produzir/vender levanta **suspeita** (cheiro, movimento, visibilidade no bairro).
- Gerenciar com: **dinheiro** (suborno/advogado), prédios de **discrição** (filtro de
  carvão pro cheiro, muros/cerca, fachada legal), e **timing**.
- Suspeita estoura → **batida policial**: multa / confisco de estoque (perda de
  dinheiro/itens). **Não é combate/shooter.**
- Vender muito no beco aumenta calor → tensão entre **produzir muito × ficar discreto**.

---

## 9. Arquitetura técnica (crítico — coop)

> O jogo é **single-player e coop**. A escolha de suportar **coop com lockstep
> determinístico** define a fundação — e não é retrofitável, por isso é construída
> desde o início mesmo pro single-player (single-player = lockstep com 1 jogador).

**Estilo visual:** câmera e gráficos **bem parecidos com Stardew Valley e Factorio**
(top-down, mundo em tiles, esteiras/máquinas no grid), mas **não em pixelart** — arte
ilustrada/limpa. Como a lógica é separada do visual, o estilo é definido pelos sprites
fornecidos, sem afetar a simulação.


- **Simulação determinística própria**, em **passo fixo (fixed tick)**, usando
  **inteiros / ponto-fixo** — **nunca** a física/float do Godot (float diverge entre
  máquinas e quebra o lockstep).
- **Godot 4.6 = apenas renderizador:** desenha o estado da simulação por cima,
  **interpolando** entre ticks pra ficar fluido.
- **Rede = lockstep determinístico (input-only):** todos os clientes rodam a mesma
  simulação idêntica; só os **inputs** trafegam ("jogador X colocou esteira em (a,b)").
  É o único modelo que escala com milhares de itens em coop.
- Invariante inegociável: **mesmos inputs → mesmo estado** (mesmo hash de estado) em
  toda máquina, todo tick. Toda iteração de coleção na sim deve ter **ordem determinística**.
- **Lógica separada do visual:** sprites (fornecidos depois) ficam em `assets/` e são
  plugados sem tocar na simulação.
- Esteiras **por células** e fluidos **por volume-de-rede** — ambos modelos discretos,
  amigáveis ao determinismo.

---

## 10. Avatar

- Movimento **livre em 8 direções** (top-down). Só as construções respeitam o grid;
  o avatar anda solto.
- **Sem craft-na-mão abstrato:** toda transformação é uma entidade física no terreno.
  O Prensado manual é uma **bancada da cozinha** que o avatar opera (chega perto,
  segura → barra de progresso).
- Inventário pequeno; carrega item na mão até as esteiras assumirem.

---

## 11. Mundo / Progressão espacial

- **Terreno finito**, começa em **casa + quintal pequeno**.
- Expande **comprando lotes** no PC (mais um item da loja, amarrado ao dinheiro).
- Recursos posicionados no mapa: **árvores** (madeira), **corpos d'água** (poço/bomba),
  **depósito de areia** (vidro).
- Começa apertado (força bom layout); cada lote novo é recompensa concreta.

---

## 12. Escopo deixado pra depois (não-objetivos do v1)

- Esteira pixel-a-pixel (contínua) — fica no modelo por células.
- Pressão de fluido por segmento — fica no volume-por-rede.
- Mapa procedural infinito — fica no terreno expansível por compra.
- Postes/fios de energia com cobertura — fica na energia global.
- Combate físico com a polícia — fica na gestão de suspeita.
- Qualidade/THC float por item — fica nas tags enum.
- Luz/nutriente no cultivo — upgrade futuro.

---

## 13. Próximos passos

1. Esqueleto do projeto Godot 4.6 (estrutura de pastas: `sim/`, `render/`, `net/`, `data/`, `assets/`, `ui/`).
2. Núcleo determinístico em passo fixo + self-check de determinismo (mesmos inputs → mesmo hash).
3. Esteira por células (1 fila de slots) jogável com 1 máquina e 1 doca.
4. Cultivo manual (loop Stardew) como primeiro gameplay vertical.
5. Integrar sprites quando fornecidos.
