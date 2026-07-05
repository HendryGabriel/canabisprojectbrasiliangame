# Weed Factory

Factory builder de cannabis (Factorio + Stardew Valley). Godot 4.6.
Design completo em [GDD.md](GDD.md).

## Rodar

Abra a pasta no Godot 4.6 (importar `project.godot`) e dê Play (F5).

## Controles

| Tecla | Ação |
|---|---|
| WASD / setas | Mover o avatar |
| E | Interagir (plantar/regar/colher, coletar/inserir em máquina, vender no beco, abrir PC) |
| E (segurar) | Operar a bancada de prensa manual |
| Hotbar (embaixo) | Escolher prédio para construir |
| Clique esquerdo | Construir |
| Clique direito | Remover (ou cancelar construção) |
| R | Girar antes de construir |
| Tab | Abrir/fechar o PC (loja) |
| Esc | Fechar loja / cancelar |

## Loop inicial

1. Plante Ruderalis nos canteiros do quintal (E: plantar → regar → colher).
2. Venda os buds no **beco** (entidade roxa à esquerda) com E.
3. Prense buds na **bancada** da cozinha (segure E) — prensado vale mais.
4. Cumpra a meta (20 buds) → Tier 1 → esteiras até máquinas, mini estufa, canos, poço.
5. Explore o mundo (gerado proceduralmente conforme você anda) até a fábrica 100% automática.

## Arquitetura (GDD §9)

- `src/sim.gd` — simulação determinística (passo fixo 10 Hz, só inteiros). Toda mutação
  entra por `cmd_*` — no coop, esses comandos viram os inputs do lockstep.
- `src/render.gd` — Godot só desenha o estado da sim (placeholders geométricos).
  Sprites definitivos entram em `assets/` substituindo o `_draw`.
- `src/player.gd` — avatar (fora da sim; injeta comandos).
- `src/ui.gd` — HUD, hotbar, loja do PC.
- `src/defs.gd` — dados estáticos (cepas, receitas, prédios, metas, lotes).

Ainda não implementado (v2): netcode do lockstep, save/load, pesquisa como camada
separada, esteiras subterrâneas/splitters.
