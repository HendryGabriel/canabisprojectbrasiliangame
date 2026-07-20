# WEEDCRAFT MVP

Este MVP cria a base jogável 3D voxel do WEEDCRAFT, incluindo autoria de estruturas, Custom Blocks e máquinas multibloco.

## Como abrir

1. Abra o Godot 4.x.
2. Escolha "Importar" ou "Abrir projeto".
3. Selecione a pasta `D:\JOGOS\WEEDCRAFT`.
4. Rode a cena principal.

## Controles

- `WASD`: mover.
- `Mouse`: olhar.
- `Espaco`: pular.
- `Clique esquerdo`: quebrar/minerar bloco.
- `Clique direito`: colocar bloco ou interagir com bau/bancada.
- `1` a `9`: selecionar hotbar.
- `E`: abrir inventario e craft pessoal 2x2.
- `Clique direito na bancada`: abrir craft 3x3.
- `Esc`: fechar painel ou abrir/fechar menu de pausa.

## Inventario

- Clique esquerdo em um slot com item: pega o stack inteiro e carrega no mouse.
- Clique esquerdo segurando um item: solta, junta ou troca com o slot clicado.
- Segurar clique esquerdo e passar por varios slots: espalha o stack igualmente entre os slots validos.
- Clique direito em um slot com item e mouse vazio: pega metade do stack.
- Clique direito segurando um item: coloca 1 item no slot.
- Segurar clique direito e passar por varios slots: coloca 1 item por slot.

## Menu e save

- O jogo abre no menu inicial.
- `Novo Jogo`: reinicia o Bioma 1 do zero.
- `Continuar`: carrega exclusivamente `user://weedcraft_save_v5.json`; saves antigos não são migrados.
- Menu de pausa: `Voltar ao jogo`, `Salvar`, `Opcoes` e `Menu inicial`.
- Opcoes: alterna tela cheia e sombras.
- O save guarda posicao do jogador, inventario, hotbar selecionada, mana, XP da Picareta de Manita, blocos alterados/removidos e conteudo dos baus.
- O mundo procedural e recriado pela seed, e o save aplica por cima as mudancas do jogador.

## O que ja existe

- Projeto Godot 4.x configurado.
- Bioma inicial 100x100 procedural, representando 1/4 do mapa final 2x2 de 200x200.
- Bordas invisiveis para impedir cair do mapa andando para fora.
- Cada coluna do terreno tem 64 blocos da grama ate a Rocha Matriz.
- Camada mais baixa de cada coluna em Rocha Matriz inquebravel.
- Cavernas procedurais no subsolo, algumas chegando perto da superficie.
- Caverna principal grande do Bioma 1: abertura no topo e tunel amplo, cilindrico e curvado ate perto da bedrock.
- Mais arvores distribuidas proceduralmente pelo Bioma 1.
- Primeira pessoa.
- Quebra e colocacao de blocos.
- Hotbar e inventario por slots quadrados com cursor de item estilo Minecraft.
- Blocos aparecem como cubos 3D renderizados nos slots do inventario e no item carregado pelo mouse; numeros de quantidade ficam pequenos no canto inferior direito.
- Hover nos slots mostra nome e descricao curta do item.
- Bau interativo com o mesmo sistema de cliques do inventario.
- Craft pessoal 2x2 no inventario.
- Craft 3x3 apenas na bancada inicial.
- Craft usa slot de resultado: ingredientes so sao consumidos quando o jogador pega o output.
- Minerios iniciais procedurais no subsolo: cobre, ferro, carvao e manita.
- Texturas aplicadas a blocos principais a partir da pasta `texture/minecraft/textures/block`.
- Blocos com textura por face no estilo Minecraft: grama, tronco, bancada e bau/barril usam topo/lado/frente/fundo apropriados.
- Inventario, craft, bau e hotbar usam icones vindos de `texture/minecraft/textures/block` e `texture/minecraft/textures/item`.
- Mana com regeneracao.
- Picareta de Manita com custo de mana e XP por uso.
- Pulo ajustado para subir um bloco.
- E possivel pular e colocar bloco diretamente abaixo para subir em torre.

## Estruturas, microvoxels e multiblocos V4

- O Estúdio começa no void com um bloco-guia ignorado até ser substituído e reutiliza a gameplay com voo criativo e inventário infinito.
- `Tab` abre as ferramentas e permite alternar entre `1x`, `1/2`, `1/4` e `1/8` na mesma grade interna `8x8x8`.
- O botão do meio copia uma formação completa de microvoxels para a hotbar e para a mão.
- A exportação oferece `Custom Block`, `Multiblock` atômico ou montável e `Estrutura` de geração.
- Custom Blocks e multiblocos usam ghost 3D, giram com `R`, validam o volume inteiro e preservam componentes referenciados.
- Montagens usam peça-âncora, mostram requisitos ausentes e só ativam a `utility_id` com peças e rotações corretas.
- Estruturas de geração alteram apenas o volume 3D autorado e não preenchem colunas acima ou abaixo.

## Receitas do MVP

- `Madeira` -> `Tabuas x4`.
- `Tabuas` em coluna de 2 -> `Gravetos x4`.
- `Tabuas` em 2x2 -> `Bancada 3x3`.
- `Tabuas` em volta da grade 3x3 -> `Bau` (somente na bancada 3x3).
- `Manita Manita Manita` na linha superior + `Graveto` no centro e embaixo -> `Picareta de Manita` (somente na bancada 3x3).

## Proximos passos sugeridos

1. Separar o mundo em chunks para suportar o mapa 200x200 completo com os 4 biomas.
2. Adicionar salvamento/carregamento.
3. Criar ferramentas comuns e tempos reais de quebra.
4. Melhorar a distribuicao de recursos do Bioma 1.
5. Criar o primeiro golem programavel.
6. Implementar o Bioma 2 no segundo grid 100x100.
