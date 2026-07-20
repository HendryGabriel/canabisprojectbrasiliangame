# Port do sistema V4 de estruturas, microvoxels e multiblocos

## Objetivo

Substituir o Blueprint V1 do WEEDCRAFT pelo sistema completo V4 validado no TRUMANCRAFT. O port inclui o Estúdio de Estruturas, microvoxels de `1x`, `1/2`, `1/4` e `1/8`, Custom Blocks, multiblocos atômicos e montáveis, componentes reutilizáveis, persistência e geração estrutural em volume 3D real.

Não haverá migração de blueprints ou saves antigos. O comportamento solicitado prevalece sobre as restrições anteriores do GDD relativas a `1/4` e microvoxels exclusivos da autoria; essas seções serão atualizadas junto com a implementação.

## Estratégia

O port reutilizará os formatos e sistemas já testados no TRUMANCRAFT, adaptando somente as integrações necessárias ao catálogo, ao mundo voxel e ao fluxo de máquinas do WEEDCRAFT. O antigo `BlueprintData` V1, o menu `F3`, a construção automática por camadas e a entrega com `G` serão removidos.

Não será criada uma biblioteca compartilhada entre os projetos nesta fase. Também não será mantido um importador V1, pois não existem assets de blueprint publicados que justifiquem a compatibilidade.

## Formato de asset V4

Um único template versionado representa quatro comportamentos:

- `structure`: conteúdo destinado ao mapa e à geração procedural;
- `custom_block`: uma célula de gameplay formada internamente por microvoxels;
- `multiblock` com `placement_mode=atomic`: um item que coloca e remove o volume inteiro;
- `multiblock` com `placement_mode=assembled`: receita espacial iniciada por uma peça-âncora.

O template contém ID estável, nome, tamanho, pivot, blocos normais, microcélulas, ar explícito, marcadores, componentes referenciados, modo de colocação, âncora, requisitos espaciais, `utility_id` e perfis de spawn quando for uma estrutura. Componentes permanecem referências canônicas e não são achatados durante a exportação.

Templates V1–V3 ainda podem ser interpretados como estruturas comuns para leitura de conteúdo autoral, mas o WEEDCRAFT não migrará saves ou blueprints V1. Toda nova exportação usa V4.

## Microvoxels

Cada célula normal possui grade interna fixa de `8x8x8`. As ferramentas colocam peças alinhadas de:

- `1x`: ocupa `8x8x8` unidades;
- `1/2`: ocupa `4x4x4` unidades;
- `1/4`: ocupa `2x2x2` unidades;
- `1/8`: ocupa uma unidade.

Peças de escalas diferentes coexistem quando seus volumes não se sobrepõem. Uma peça maior nunca substitui silenciosamente microvoxels existentes: se não couber, é alinhada à próxima posição válida na face mirada ou a colocação é rejeitada. Quando uma peça maior cruza uma ocupação irregular, ela pode ser decomposta em peças menores alinhadas, preservando os vazios autorados.

Cada peça mantém suas próprias faces e repetição de textura. Contato com microvoxels não altera UVs nem suprime faces de blocos normais. O ghost e a borda de seleção mostram exatamente o volume que será afetado.

## Estúdio de Estruturas

O Estúdio reutiliza a movimentação e interação da gameplay, com voo criativo, inventário infinito e todos os materiais disponíveis. O workspace começa no void com somente um bloco-guia central destacado; ele é ignorado até ser substituído.

`Tab` abre a roda de ferramentas. O tamanho selecionado aparece no topo e altera diretamente o método normal de construção, sem exigir um botão adicional. A hotbar aceita scroll. O botão do meio copia uma célula inteira, inclusive a formação de microvoxels, e cria um padrão reutilizável visível na hotbar e na mão.

O seletor de exportação oferece:

- `Custom Block`;
- `Multiblock`, escolhendo item inteiro ou montagem por peças;
- `Estrutura`.

A ferramenta de âncora marca a peça inicial de um multibloco montável. Assets salvos no projeto entram no catálogo criativo do Estúdio e podem ser usados como componentes de assets maiores. Undo/redo trata cada colocação, remoção ou transformação composta como uma operação coerente.

## Gameplay e colocação

Custom Blocks e multiblocos atômicos são itens reais. Ao mirar uma superfície, o jogo apresenta um ghost com a geometria completa; `R` gira em passos de 90 graus. A colocação valida todos os voxels, limites, colisão com o jogador e reservas de outras montagens antes de escrever qualquer célula. Falha parcial executa rollback. Quebrar qualquer célula pertencente ao asset remove a instância inteira e produz somente um item.

Multiblocos montáveis iniciam uma receita espacial quando a peça-âncora é colocada. As posições ausentes aparecem como ghosts. Segurar a peça correta destaca posições compatíveis; cada requisito valida `asset_id`, coordenada e rotação. Uma peça errada ou girada incorretamente não ocupa a reserva.

Ao completar todos os requisitos, a máquina é ativada. Remover qualquer peça a desativa sem apagar as demais; recolocar a peça correta restaura a mesma instância e seu estado persistente.

## Utilidades

Assets não carregam código arbitrário. `utility_id` aponta para um handler registrado centralmente pelo WEEDCRAFT. O contrato permite ativação, desativação, interação, tick determinístico e serialização do estado específico.

Uma utilidade desconhecida gera aviso informativo com o ID do asset e da utilidade, mas não impede carregar, renderizar, posicionar, quebrar ou salvar a geometria. Lógica autoritativa de máquinas deverá entrar pelo estado e pelos comandos determinísticos do WEEDCRAFT; apresentação e ghosts não decidem resultados da simulação.

## Estruturas e geração

Estruturas alteram somente blocos, microcélulas e ar explícito dentro do volume 3D autorado. Marcadores de fundação validam apoio, mas não criam colunas verticais. Cavernas fora do volume permanecem intactas.

O spawn graph define condições de superfície, caverna ou subsolo, bioma, cota mínima/máxima/exata, frequência, distância e limite por bioma. A reserva usa AABB 3D contido no bioma de origem. Componentes referenciados são materializados durante a geração, mas sua identidade é preservada no relatório e no runtime.

## Catálogo e persistência

Um registro unificado descobre estruturas, Custom Blocks e multiblocos, valida IDs duplicados, referências ausentes, ciclos de componentes, peças-âncora ambíguas e requisitos inválidos. Custom Blocks e multiblocos atômicos entram no catálogo de itens; montagens usam seus itens componentes.

O novo save guarda instâncias colocadas, asset ID, origem, rotação, modo montado/atômico, estado da utilidade e progresso das receitas espaciais. O carregamento reconstrói ownership e reservas a partir do registro atual. Hashes incompatíveis ou assets ausentes geram erro claro em vez de corromper o mundo.

## Tratamento de erros

- Exportações inválidas são recusadas antes de substituir o arquivo existente.
- Referências ausentes, IDs duplicados, ciclos e âncoras inválidas aparecem como diagnósticos do registro.
- Colocação nunca deixa uma instância parcialmente escrita.
- Utilidade ausente é aviso não fatal.
- Save com asset inexistente ou formato incompatível é recusado com mensagem explícita.
- Falha de geração registra seed, bioma, candidato e razão de rejeição para facilitar suporte posterior.

## Verificação

A implementação terá regressões para:

- serialização V4 e leitura de templates V1–V3 como estruturas comuns;
- coexistência, textura e colisão de peças `1x`, `1/2`, `1/4` e `1/8`;
- fluxo do Estúdio, inventário infinito, padrões copiados e exportação dos três tipos;
- colocação/rotação/quebra atômica e rollback;
- âncora, ghosts, peça e rotação corretas, ativação e desativação de montagens;
- registro e aviso de `utility_id` ausente;
- save/load de instâncias e estado;
- componentes referenciados dentro de estruturas geradas;
- preservação de cavernas fora do volume 3D;
- cena principal e regressão voxel ampla;
- repetição de comandos autoritativos com hash final idêntico.

## Fora do escopo

- Migração de Blueprint V1 ou saves antigos;
- addon compartilhado entre TRUMANCRAFT e WEEDCRAFT;
- implementação das utilidades específicas de todas as futuras máquinas;
- networking completo; o port apenas preserva o caminho para comandos e estado determinísticos.
