# Godot Map Editor

Ferramenta local para montar mapas em grid 16x16 usando spritesheets PNG e manifestos JSON gerados pelos editores de sprites do projeto.

## Abrir

Abra `tools/godot_map_editor/index.html` no navegador.

## Fluxo

1. Clique em `Importar PNG + JSON`.
2. Selecione um ou mais `.png` junto com seus `.json`.
3. Escolha um sprite na lista.
4. Pinte no canvas usando as camadas de tilemap ou decoracao.
5. Ajuste pivot, tipo e colisao do sprite selecionado quando necessario.
6. Confira em `Atlases importados` se o caminho Godot aponta para o arquivo correto, por exemplo:
   `res://src/ASSETS/STATIC/Vegetation.png`.
7. Exporte:
   - `Salvar projeto`: arquivo completo do editor, com imagens embutidas para reabrir depois.
   - `Exportar Godot JSON`: mapa leve para importar na Godot.
   - `Exportar Importador`: baixa uma copia do script de importacao.

## Importar na Godot

O arquivo `godot_map_importer.gd` pode ser colocado em qualquer Node da cena:

1. Anexe o script a um Node.
2. Aponte `map_json_path` para o JSON exportado.
3. Opcionalmente escolha `target_parent_path`.
4. Marque `rebuild_in_editor` no inspetor.

O importador cria uma arvore `Node2D` com `Sprite2D` recortados via `AtlasTexture` e `StaticBody2D` para os sprites com colisao.
