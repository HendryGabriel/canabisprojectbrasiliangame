# WEEDCRAFT — desenho da revisão do plano de implementação

Data: 2026-07-12

## Objetivo

Alinhar integralmente o guia do repositório e o plano de implementação ao GDD atual: factory builder 3D voxel em primeira pessoa, Godot 4.7, mapa fixo, simulação determinística compartilhada entre single-player e coop. Corrigir o roadmap para que cada fase tenha dependências acíclicas, critérios verificáveis e cobertura explícita do GDD.

## Autoridade e escopo

- `GDD.md` é a autoridade de produto.
- WEEDCRAFT permanece 3D voxel em primeira pessoa; a direção 2D não será mantida como alternativa nem mencionada nos documentos finais.
- Godot 4.7 é a versão do produto e do projeto.
- “Horário de operação” será removido do GDD por decisão do usuário.
- Suborno e horário de operação não farão parte do sistema de calor.
- `AGENTS.md` será atualizado para refletir o produto 3D e suas regras técnicas.
- O estado herdado de TRUMANCRAFT continuará descrito apenas como realidade da implementação atual.
- Não haverá refatoração ampla do protótipo, mudança de engine, commit ou alteração de sistemas de jogo nesta revisão documental.

## Estratégia escolhida

Reconstruir o conteúdo do plano HTML preservando sua identidade visual. O documento passará a usar HTML semântico e conteúdo estático, com `<details>` e `<summary>` para as fases. JavaScript não será necessário para consultar o roadmap, imprimir o documento ou navegar por teclado.

## Contrato técnico do plano

O plano deve tornar obrigatórios desde a fundação:

- tick fixo e estado autoritativo em inteiros ou ponto fixo;
- single-player passando pela mesma fila de comandos do coop;
- envelope canônico de comando com tick, jogador, sequência, tipo e payload;
- ordenação total e explícita de comandos e entidades;
- snapshots, replay e hash canônicos, versionados e independentes da ordem de `Dictionary`;
- posição, movimento, colisão e alcance do avatar resolvidos pela simulação; `CharacterBody3D`, raycasts e transforms servem apenas para apresentação e coleta de intenção;
- apresentação interpolada sem realimentar o estado autoritativo;
- testes de dois runners desde o primeiro sistema autoritativo, com ordens de inserção e timing visual diferentes;
- save-and-continue equivalente a uma execução ininterrupta;
- transporte de rede coop somente depois de um vertical slice local determinístico.

## Roadmap aprovado

1. **Contrato e matriz de migração.** Classificar os componentes atuais como reutilizar na apresentação, adaptar temporariamente, substituir ou aposentar após um gate.
2. **Núcleo determinístico.** Comandos, tick, IDs, reducers, snapshots, replay, serialização e hash.
3. **Mapa fixo e regiões.** Asset autoral versionado, `QUINTAL`, `CIDADE`, `ROTA_FIXA`, `BLOQUEADO` e permissões.
4. **Avatar autoritativo.** Movimento livre, colisão voxel, pulo, alcance, interação e interpolação 3D.
5. **Itens, cepas, inventário e cultivo manual.** Catálogo completo, Blend, Ruderalis, plantio, água, crescimento e colheita.
6. **Economia e venda manual.** Dinheiro compartilhado, PC para suprimentos iniciais, NPC para venda e capacidade limitada do avatar.
7. **Vertical slice da fábrica.** Uma machine fixture versionada, tubos retos/curvas/subida, Terminal de Entrega e venda automática.
8. **Save e diagnóstico.** Round-trip, continuação determinística, hashes por tick e relatório de primeira divergência.
9. **Runtime de schematics.** Pesquisa mínima, ghost, manifesto, `machine_block_id`, catálogo do NPC, canteiro e ativação completa.
10. **Coop lockstep.** Transporte de comandos, input delay, no-op, conflitos, desconexão e diagnóstico de desync.
11. **Oficina de autoria.** Microvoxels, blocos-módulo, validação e exportação canônica de `SchematicData`.
12. **Água e energia.** Volume compartilhado, energia global, conta proporcional ao consumo, brownout de máquinas e tubos, solar e biomassa.
13. **Cultivo automático.** Mini estufa, grande estufa e produção automática de sementes por cepa.
14. **Processamento e logística.** Prensado, Pura, Blend, Haxixe, Ice, CBD, Baseado, madeira, seda, gelo, vidro, junções e filtros.
15. **Calor, progressão e vitória.** Cheiro, movimento, visibilidade e volume; filtros de carvão, muros, cercas e fachada legal; multa/confisco, metas, pesquisa e sandbox após a vitória.
16. **Arte, UI, desempenho e release.** Assets substituíveis, acessibilidade, feedback, balanceamento, orçamento mensurável, regressões e pendências técnicas reais.

Cada fase dependerá apenas de fases anteriores. O HTML mostrará IDs de fase e dependências explícitas, e cada definição de pronto será alcançável usando somente o que já estiver concluído.

## Cobertura obrigatória do GDD

O plano incluirá uma matriz que ligará cada seção do GDD a uma ou mais fases e regressões. A cobertura precisa mencionar explicitamente:

- todas as cepas, ordem de progressão e exclusão da Ruderalis de blends;
- item `{produto, cepa}`, stacks e receitas parametrizadas;
- Prensado físico/manual e todas as cadeias de processamento;
- produção automática de sementes;
- tubos que não perdem itens quando bloqueados e arbitragem determinística em junções;
- PC vendendo sementes, materiais iniciais, tubos e upgrades;
- NPC comprando produtos e vendendo somente blocos de schematics pesquisadas;
- `machine_block_id` como item empilhável transportado e instalado manualmente;
- schema, versão, hash, envelope, portas, rotações, espelhamento, peças e rejeições de `SchematicData`;
- água por volume de rede, energia global, conta de luz e brownout;
- calor sem combate, suborno ou horário de operação;
- venda manual, automática, rota protegida, vitória e continuação do sandbox;
- estado compartilhado e resolução determinística de conflitos no coop;
- todos os não objetivos do v1.

## Estrutura do HTML

O documento terá:

- cabeçalho com versão, autoridade, nota anterior e critérios da nota 10;
- contrato do produto e baseline real do repositório;
- diagrama textual das camadas e fluxo de comandos;
- roadmap de 16 fases em conteúdo HTML estático;
- em cada fase: objetivo, escopo, entregáveis, dependências, definição de pronto, testes e exclusões;
- gates do vertical slice, alpha determinístico, coop e release;
- matriz de rastreabilidade GDD → fase → teste;
- riscos e respostas concretas;
- lista unificada de não objetivos;
- checklist final de release.

O CSS será responsivo, imprimível e compatível com `prefers-reduced-motion`. A navegação e expansão funcionarão com recursos nativos do navegador. A estrutura não dependerá de JavaScript e não usará ARIA para recriar controles que já existem semanticamente.

## Verificação documental

Após as edições:

1. conferir ausência de `TODO`, `TBD`, “suborno”, “horário de operação”, direção 2D e Godot 4.6 nos documentos atualizados;
2. conferir que o HTML contém exatamente 16 fases com IDs únicos e dependências somente regressivas;
3. validar balanceamento de tags e a ausência de referências a elementos inexistentes;
4. conferir que todas as seções 1–13 do GDD aparecem na matriz de rastreabilidade;
5. conferir manualmente as regras de cepas, lojas, schematics, tubos, energia, calor, coop e não objetivos;
6. revisar o diff para preservar alterações não relacionadas do usuário.

## Critério de sucesso

O resultado recebe nota 10 quando um implementador consegue escolher qualquer fase, identificar pré-condições, arquivos conceituais, entregáveis, testes e gate de saída sem depender de decisões implícitas; e quando nenhuma fase exige um sistema futuro ou contradiz o GDD e o guia.
