# Criaturas, combate, iluminacao e thumbstone

Data: 2026-07-10

## Objetivo

Adicionar a primeira fatia jogavel de criaturas ao TRUMANCRAFT: um fantasma hostil que voa baixo, persegue e ataca o jogador; um coelho passivo que anda pela superficie e evita cavernas; combate corpo a corpo com qualquer item; tochas que iluminam e reduzem spawn; e recuperacao do inventario por uma thumbstone apos a morte.

O visual inicial das criaturas sera provisório. Comportamento, colisao, atributos e animacao ficarao separados do `VisualRoot`, permitindo trocar os prototipos por modelos 3D animados sem reescrever a IA ou o combate.

## Escopo

Esta entrega inclui:

- vida, dano, morte e respawn do jogador;
- ataques do jogador por clique esquerdo, sem cooldown artificial;
- dano baseado no item da hotbar;
- base reutilizavel para criaturas;
- fantasma hostil e coelho passivo;
- spawn dinamico por ambiente, horario e luz;
- tochas fabricaveis, colocaveis e persistentes;
- marcadores de spawn para estruturas especiais;
- thumbstone persistente com recuperacao automatica de itens;
- HUD de vida e feedback minimo de dano;
- testes automatizados e roteiro de verificacao manual.

Ficam fora deste marco: drops de criaturas, criacao/reproducao, dialogos de NPC, domesticacao, armaduras, durabilidade, ataques a distancia, pathfinding global, salvamento individual de criaturas temporarias e modelos 3D finais.

## Arquitetura

### Entidades

`EntityManager` pertence a cena principal e administra spawn, limites, descarte por distancia e referencias das criaturas ativas. Criaturas dinamicas nao entram no save; ao carregar o mundo, o gerente volta a popula-lo pelas mesmas regras.

Uma cena/script `Creature` concentra corpo fisico, vida, recebimento de dano, morte e sinais de estado visual. Cada criatura possui um filho `VisualRoot`. A IA publica os estados `idle`, `move`, `attack`, `hurt` e `death`; o prototipo reage com transformacoes simples, enquanto um modelo futuro podera mapear os mesmos estados para `AnimationPlayer` ou `AnimationTree`.

`Ghost` e `Rabbit` especializam apenas movimento, selecao de alvo e transicoes de estado. Atributos de balanceamento ficam exportados/configuraveis, sem uma camada adicional de banco de dados neste primeiro marco.

### Combate

O clique esquerdo executa uma unica consulta fisica a partir da camera ate o alcance atual de interacao. O primeiro colisor decide o resultado: criatura atacavel recebe o golpe; um voxel bloqueia o ataque e segue o fluxo existente de quebra. Isso impede ataques atraves de paredes.

Cada evento de clique pode causar um golpe. Nao existe cooldown do jogador e segurar o botao nao vira ataque automatico: a velocidade depende de cliques sucessivos. Um clique nunca acerta mais de uma criatura.

O catalogo de itens passa a expor `attack_damage`, calculado ou declarado assim:

| Item na mao | Madeira | Pedra | Ferro |
| --- | ---: | ---: | ---: |
| Espada | 5 | 10 | 15 |
| Picareta, machado, pa ou enxada | 2,5 | 5 | 7,5 |
| Bloco, outro item ou mao vazia | 1 | 1 | 1 |

A picareta de manita usa 7,5 neste marco, acompanhando o maior nivel de ferramenta existente enquanto nao houver uma espada de manita definida. Vida e dano aceitam `float` para preservar os meios pontos.

O jogador comeca com 20 de vida. O fantasma tem 20 de vida, causa 2 de dano por contato de ataque e respeita 1 segundo entre ataques. O coelho tem 5 de vida e pode ser ferido e morto. Esses valores sao configuraveis para balanceamento posterior.

### IA e movimento

O fantasma alterna entre `wander`, `chase`, `attack` e retorno a `wander`. Ele flutua entre 1 e 2 blocos acima do piso detectado, escolhe destinos locais e usa sondas/raycasts para desviar de voxels. Nao atravessa blocos e nao depende de `NavigationMesh`, pois o terreno voxel pode ser editado em tempo real. Ele detecta o jogador por distancia e linha de visao, persegue enquanto o alvo continuar valido e ataca apenas em alcance curto.

O coelho usa movimento terrestre com pequenos saltos. Antes de aceitar um destino, verifica piso, espaco livre, desnivel e exposicao ao ceu. Pontos classificados como caverna, entradas de caverna ou areas sem ceu visivel sao rejeitados. Ele tambem recua de bordas com queda perigosa. O coelho nao persegue nem ataca.

### Spawn e escuridao

O `EntityManager` faz tentativas espaçadas, em vez de procurar pontos a cada frame. Candidatos ficam inicialmente entre 12 e 32 blocos do jogador, fora da visao imediata e com espaco fisico suficiente. Quantidades maximas e intervalos sao configuraveis.

Para o fantasma, um ponto e escuro quando satisfaz uma destas condicoes:

- esta na superficie durante a noite;
- esta sob cobertura voxel, dentro de uma caverna;
- pertence a uma estrutura especial por marcador de spawn.

Em todos os casos, o candidato e rejeitado se estiver dentro do raio logico de uma tocha. Estruturas especiais usam um novo marcador `entity_spawn` no asset, com `entity_id: "ghost"`; isso evita fazer uma estrutura inteira funcionar como zona implicita. O marcador ainda precisa ter espaco valido e escuridao, e a tocha continua podendo suprimi-lo.

Coelhos tentam nascer apenas durante o dia, sobre superficies abertas e com ceu visivel. Cavernas, entradas de cavernas e estruturas subterraneas sao sempre rejeitadas para coelhos.

Criaturas muito distantes podem ser removidas para manter custo previsivel, desde que nao estejam em combate visivel. Como elas nao carregam inventario nem estado persistente neste marco, o descarte nao perde progresso do jogador.

### Tochas e iluminacao hibrida

A tocha e adicionada ao catalogo como item/bloco fabricavel por um carvao sobre um graveto. Ela usa a colocacao e quebra de voxels existente.

Cada tocha colocada cria uma representacao visual e um `OmniLight3D` de curto alcance, alem de ser registrada no `LightRegistry`. O registro oferece consulta espacial de fontes proximas; o raio logico inicial de supressao de spawn e 8 blocos. A luz visual e a regra logica usam a mesma origem, mas nao tentam simular propagacao de luz voxel.

Colocar, quebrar, gerar ou carregar uma tocha atualiza o registro. Para evitar uma luz por bloco distante custosa, luzes visuais so ficam ativas dentro de uma distancia configuravel do jogador; a fonte logica continua registrada para spawn. O bloco salvo e a fonte de verdade, permitindo reconstruir o registro ao carregar e corrigir qualquer dessincronizacao.

### Morte, respawn e thumbstone

Ao chegar a zero de vida, o jogador para de receber entrada de combate. O sistema copia todos os slots do inventario/hotbar para uma thumbstone, limpa os slots do jogador e procura uma posicao segura perto do local da morte: celula livre com piso solido, dentro dos limites do mundo. Se o ponto exato for invalido, a busca expande localmente; se nenhum ponto for encontrado, usa o ponto seguro de spawn.

O jogador reaparece no spawn com vida cheia. A thumbstone e uma entidade persistente, com identificador unico, posicao e lista de slots. Quebra-la ou usar Shift sobre ela chama a mesma operacao de coleta automatica. Os itens sao empilhados e preenchidos no inventario do jogador; se tudo couber, a thumbstone desaparece. Se faltarem slots porque o jogador coletou novos itens apos morrer, ela permanece com apenas o excedente e mostra uma mensagem clara.

Thumbstones nao expiram e multiplas mortes podem criar multiplas pedras. Salvar e carregar preserva todas elas e seu conteudo. A transferencia atualiza primeiro os dados em memoria e depois a interface, evitando duplicacao por dois eventos de interacao no mesmo frame.

## Fluxos principais

### Ataque do jogador

1. O jogo recebe um clique esquerdo enquanto nenhum menu esta aberto.
2. Um raycast encontra o primeiro colisor no alcance.
3. Se for uma criatura atacavel, o catalogo resolve o dano do item selecionado e a criatura recebe um unico golpe.
4. Se for voxel, continua o fluxo existente de quebra.
5. O visual recebe o estado `hurt`; ao zerar a vida, recebe `death` e a entidade e removida apos o feedback visual.

### Ataque do fantasma

1. O fantasma encontra o jogador em alcance de deteccao e com linha de visao.
2. Muda de `wander` para `chase` e procura uma rota local livre.
3. Ao entrar no alcance curto e ter o temporizador liberado, muda para `attack` e aplica 2 de dano.
4. Se a vida do jogador zerar, inicia o fluxo atomico de thumbstone e respawn.

### Tentativa de spawn

1. O gerente escolhe alguns candidatos no anel permitido.
2. Classifica superficie, caverna ou marcador de estrutura e valida horario/especie.
3. Rejeita ponto visivel, ocupado, iluminado por tocha ou acima do limite populacional.
4. Instancia a criatura escolhida com visual provisório.

## Persistencia

O formato de save ganha uma nova versao e passa a guardar vida atual do jogador, thumbstones e dados necessarios para reconstruir tochas. Os voxels ja salvos continuam sendo a fonte de verdade para tochas; nao se salva uma segunda lista autoritativa de luzes.

O carregador aceita saves anteriores: vida ausente vira 20 e a lista de thumbstones ausente vira vazia. Dados de thumbstone invalidos sao ignorados com aviso, sem impedir o restante do mundo de carregar. Criaturas temporarias nunca sao serializadas.

## Tratamento de falhas e limites

- Raycasts sem alvo nao causam dano nem quebram bloco.
- Um alvo libertado entre input e aplicacao do golpe e ignorado com seguranca.
- Uma tocha removida por geracao, edicao ou carregamento e reconciliada a partir dos voxels.
- Spawn falha silenciosamente quando nao encontra ponto valido; nao força criatura dentro de parede.
- A IA abandona um destino bloqueado, escolhe outro e possui limite de tentativas para nao consumir frame indefinidamente.
- Uma thumbstone nunca apaga itens que nao couberem no jogador.
- Interacoes concorrentes com thumbstone usam uma trava curta/estado `collecting` para impedir duplicacao.
- Posicoes persistidas fora dos limites sao corrigidas para um ponto seguro ou ignoradas quando nao ha recuperacao segura.

## Estrategia de testes

### Automatizados

- tabela de dano para cada espada, cada familia de ferramenta, bloco, item comum e mao vazia;
- um clique produz exatamente um golpe e a parede bloqueia o alvo;
- vida fracionaria, morte e sinais de estado da criatura;
- transicoes basicas do fantasma entre vagar, perseguir e atacar;
- rejeicao de spawn de fantasma durante o dia na superficie;
- aceitacao noturna, em caverna e em marcador especial quando escuro;
- supressao de spawn dentro de 8 blocos de uma tocha e permissao fora do raio;
- coelho aceita superficie diurna aberta e rejeita caverna/entrada/celula sem ceu;
- morte move exatamente todos os slots para a thumbstone e limpa o jogador;
- quebra e Shift usam a mesma coleta, sem duplicar itens;
- excedente permanece na thumbstone;
- round-trip do save preserva vida, tochas e thumbstones;
- migracao de save anterior cria valores padrao validos.

### Verificacao manual

- clicar rapidamente com mao, bloco, ferramenta e espada e observar os danos esperados;
- tentar atacar fantasma atras de parede;
- observar fantasma vagar baixo, perseguir, contornar obstaculos e atacar;
- observar coelho saltar na superficie sem entrar em caverna ou cair em precipicio;
- confirmar spawn noturno, subterraneo e em estrutura especial;
- cercar uma area com tochas e confirmar luz visual e ausencia de novos fantasmas;
- morrer com inventario cheio, criar novos itens e recuperar a thumbstone com excedente;
- salvar/carregar com tochas e varias thumbstones;
- substituir `VisualRoot` por uma cena com `AnimationPlayer` de teste sem alterar IA/combate;
- executar o benchmark existente para verificar que spawn e luzes proximas nao degradam o alvo de desempenho de forma relevante.

## Ordem recomendada de implementacao

1. Modelo de vida/dano e resolucao de dano pelo catalogo.
2. Raycast unificado de ataque/quebra e HUD de vida.
3. `Creature` base, visuais provisórios e testes de dano.
4. Coelho terrestre com validacao de superficie e cavernas.
5. Fantasma com maquina de estados, perseguicao e ataque.
6. Tocha, `LightRegistry`, luz visual e persistencia.
7. `EntityManager`, regras de escuridao, limites e spawn ambiental.
8. Marcador `entity_spawn` nas estruturas especiais.
9. Morte, respawn, thumbstone, coleta e migracao do save.
10. Testes integrados, roteiro manual e medicao de desempenho.

## Criterios de aceite

A entrega esta completa quando os danos definidos funcionarem por clique sem atravessar paredes; fantasma e coelho andarem segundo suas regras; o fantasma nascer somente em pontos escuros permitidos e fora da protecao de tochas; o coelho nunca escolher cavernas; o fantasma perseguir e atacar o jogador; a morte criar uma thumbstone sem perder ou duplicar itens; e save/load preservar tochas, vida e thumbstones. A troca do visual provisório por uma cena 3D animada deve exigir apenas a conexao dos cinco estados visuais, sem mudancas na IA ou no combate.
