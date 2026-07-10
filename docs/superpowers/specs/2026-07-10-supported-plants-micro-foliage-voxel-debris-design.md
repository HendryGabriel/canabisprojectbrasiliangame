# Plantas com Suporte, Microfolhagem e Partículas Voxel

## Objetivo

Adicionar três melhorias visuais e funcionais ao motor voxel finito sem reintroduzir nodes por bloco e preservando a meta de 120 FPS no preset Performance:

1. Plantas dependem de um bloco sólido imediatamente abaixo e são removidas quando esse suporte desaparece.
2. Blocos de grama e folhas recebem microgeometria que altera sua silhueta e reage ao vento e ao jogador.
3. A mineração emite fragmentos com cores extraídas da textura do bloco durante o progresso e em uma explosão final.

## Princípios de desempenho

- Nenhum node é criado por bloco, lâmina ou partícula.
- Microgeometria é produzida pelos workers junto da malha da seção.
- Todas as seções compartilham o mesmo material de microfolhagem.
- Posição e velocidade do jogador são parâmetros globais atualizados uma vez por frame.
- Partículas usam um único `MultiMeshInstance3D` com capacidade fixa.
- Edições dependentes são agrupadas e cada seção é enfileirada no máximo uma vez por transação.
- High e Performance usam limites explícitos e mensuráveis.

## Plantas dependentes de suporte

Todos os blocos com `plant = true` no `BlockCatalog` exigem um bloco sólido imediatamente abaixo.

### Remoção

Um `VoxelDependencyResolver` recebe uma alteração autoritativa e resolve dependências antes do rebuild:

1. Remove o bloco solicitado.
2. Verifica a célula imediatamente acima.
3. Se ela contiver uma planta e o novo bloco inferior não for sólido, remove a planta.
4. Repete a verificação acima da planta removida para suportar futuras dependências empilháveis, com limite igual à altura do mundo.
5. Retorna uma lista de `EditResult`, drops e seções afetadas sem modificar a SceneTree.

Uma planta removida por perda de suporte gera o mesmo drop de uma quebra normal. Bedrock, limites e biomas bloqueados continuam respeitados.

### Colocação e geração

- Colocação de plantas falha quando a célula inferior está vazia, contém planta ou bloco não sólido.
- Estruturas e geração validam a mesma regra antes de aplicar plantas.
- O Estúdio de Estruturas usa a regra durante construção criativa, mas ar explícito e templates continuam podendo representar o estado desejado; templates inválidos são sinalizados na exportação.

### Coalescimento

O chamador reúne todas as posições afetadas, atualiza drops/metadados e chama `queue_sections` uma vez. Revisões continuam sendo incrementadas pelo `VoxelWorld`; resultados de worker obsoletos seguem descartados.

## Microgeometria de grama e folhas

`VoxelSectionMesher` passa a retornar uma classe adicional, `micro_foliage`, separada de `opaque`, `cutout` e `transparent`.

### Grama

- Somente blocos `grass` com face superior exposta geram microgeometria.
- Cada bloco gera lâminas verticais finas e determinísticas, posicionadas em coordenadas alinhadas aos pixels 16x16.
- A base fica no topo do cubo; as pontas ultrapassam a face entre 1/16 e 3/16 de bloco.
- Os UVs usam pequenas regiões da textura superior da própria grama.

### Folhas

- Blocos `leaves` geram saliências nas faces expostas.
- Faces encostadas em folhas ou em outro bloco opaco não geram saliências internas.
- Cada saliência se projeta perpendicularmente à face entre 1/16 e 3/16 de bloco.
- Os UVs usam a textura da face correspondente da folha.
- Microfolhagem não entra no `ConcavePolygonShape3D` e não afeta raycast DDA.

### Determinismo e atributos

- Posição, altura, orientação e seleção de UV derivam de um hash inteiro da posição global, face e índice da lâmina.
- O worker grava peso de dobra nos atributos de vértice: zero na base e um na ponta.
- A direção da face é codificada nos atributos para o shader empurrar a geometria corretamente.
- O mesmo snapshot e preset sempre produzem arrays idênticos.

## Shader compartilhado de microfolhagem

`VoxelTextureArray` fornece um material `micro_foliage` com texture array, alpha scissor e filtro nearest.

Parâmetros globais:

- `voxel_player_position`
- `voxel_player_velocity`
- `voxel_foliage_interaction_radius`
- `voxel_foliage_wind_strength`
- `voxel_foliage_render_distance`

O vertex shader soma duas deformações apenas nos vértices com peso de ponta:

1. Vento senoidal com fase derivada da posição mundial e duas frequências para evitar movimento uniforme.
2. Inclinação para longe dos pés do jogador, orientada pela velocidade horizontal e atenuada suavemente pelo raio.

Sem jogador válido, os parâmetros de interação ficam zerados e apenas o vento continua. A deformação não altera o cubo base nem exige rebuild de seção.

## Qualidade e distância

### High

- Grama: quatro grupos de lâminas por topo exposto.
- Folhas: até quatro grupos por face exposta.
- Distância de microfolhagem: 80 blocos.
- Sombras seguem a configuração High.

### Performance

- Grama: dois grupos por topo exposto.
- Folhas: até dois grupos por face exposta, com seleção checkerboard determinística.
- Distância de microfolhagem: 40 blocos.
- Sombras desativadas.

Trocar o preset invalida e reconstrói as seções uma vez para mudar a densidade física dos arrays. Distância e interação continuam sendo controles de shader/visibilidade.

## Sistema de fragmentos voxel

Adicionar `VoxelDebrisSystem`, proprietário de um `MultiMeshInstance3D` e arrays compactos de estado.

### Pool

- High: 256 slots.
- Performance: 96 slots.
- Cada slot guarda posição, velocidade, rotação, velocidade angular, idade, duração, escala e cor.
- Quando o pool estiver cheio, o slot ativo mais antigo é reutilizado.
- Slots inativos recebem transform fora da área visível; não há criação/destruição de nodes durante gameplay.

### Aparência

- O mesh compartilhado é um pequeno fragmento cúbico.
- `MultiMesh` usa cor por instância.
- `VoxelTexturePaletteCache` lê as imagens originais do catálogo, normaliza para RGBA8 e guarda somente pixels com alpha suficiente.
- A face atingida seleciona `top`, `bottom`, `front` ou `side` usando o normal do `VoxelHit`.
- Cada fragmento escolhe deterministicamente uma cor da paleta da face.
- Se a textura estiver ausente ou vazia, usa `color` do bloco.

### Emissão durante a quebra

- Um acumulador temporal emite fragmentos enquanto o alvo e o progresso permanecem válidos.
- Origem fica levemente à frente da face atingida para evitar z-fighting.
- Velocidade inicial combina normal da face, dispersão tangencial e pequena elevação.
- A taxa cresce moderadamente com o progresso.
- Cancelar a quebra interrompe novas emissões, sem apagar partículas existentes.

### Explosão final

- Após a remoção autoritativa, uma rajada parte do centro do bloco.
- High emite de 28 a 36 fragmentos; Performance, de 12 a 18.
- Quebra instantânea no Estúdio Criativo emite apenas essa rajada.
- Drops de inventário continuam separados dos fragmentos visuais.

### Movimento

- Atualização CPU percorre somente slots ativos.
- Gravidade, rotação e fade são calculados sem corpos físicos.
- Cada fragmento pode executar no máximo uma consulta voxel simples ao cruzar o chão e quicar uma única vez.
- Vida máxima curta, entre 0,45 e 1,1 segundo.

## Integração

### Gameplay

- `_handle_block_breaking` informa alvo, normal, bloco e progresso ao `VoxelDebrisSystem`.
- `_cancel_block_breaking` encerra emissão contínua.
- `_complete_block_breaking` dispara a rajada depois que a edição for aceita.
- O resolvedor de dependências produz remoções secundárias e drops antes de enfileirar seções.

### Estúdio de Estruturas

- Quebra criativa usa o mesmo resolvedor de suporte no `StructureWorkspace`.
- A explosão final usa o mesmo sistema de debris e paletas.
- Ferramentas em massa podem suprimir partículas para não criar ruído visual ou saturar o pool.

### Renderizador de seções

- `VoxelSectionSystem` mantém um `MeshInstance3D` persistente para a superfície `micro_foliage` de cada seção não vazia.
- Upload e swap seguem o mesmo orçamento e revisão das superfícies atuais.
- O `MeshInstance3D` de microfolhagem usa `visibility_range_end` de 80 blocos em High e 40 em Performance; fora do alcance ele não é desenhado nem considerado para sombras.

## Falhas e compatibilidade

- Blocos sem textura usam a cor fallback.
- Blocos desconhecidos não geram microfolhagem.
- Falta de jogador desativa somente a interação local.
- Pool cheio reutiliza slots sem alocação.
- Saves V3 e paleta permanecem inalterados.
- Microfolhagem e debris são dados derivados e nunca entram no save.
- Rebuilds obsoletos continuam descartados por revisão.

## Testes

- Planta é removida e gera drop ao perder suporte.
- Planta não pode ser colocada sem suporte sólido.
- Cascata em borda de seção reúne todos os vizinhos e enfileira uma vez.
- Grama gera microgeometria somente com topo exposto.
- Folha gera saliências somente nas faces expostas.
- High e Performance geram densidades esperadas.
- Arrays de microgeometria são determinísticos.
- Microgeometria não aparece no collider.
- Shader contém vento, interação, distância e alpha scissor.
- Paletas ignoram pixels transparentes e escolhem a textura correta por face.
- Pool nunca excede 256/96 slots.
- Emissão contínua, cancelamento, explosão final, fade e quique único funcionam.
- Estúdio Criativo usa explosão sem emissão contínua.
- Regressão headless completa permanece limpa.
- No hardware-alvo com Performance, benchmark F9 mantém p95 <= 8,33 ms e p99 <= 16,67 ms.

## Ordem de implementação

1. Resolver dependências de suporte e agrupar edições/drops.
2. Adicionar descritores de microfolhagem ao catálogo/paleta.
3. Gerar `micro_foliage` no mesher e fazer upload persistente por seção.
4. Implementar shader global de vento/interação e integração de presets.
5. Implementar cache de paletas de textura.
6. Implementar `VoxelDebrisSystem` com pool MultiMesh.
7. Integrar mineração normal e quebra criativa.
8. Adicionar regressões e executar benchmark manual.
