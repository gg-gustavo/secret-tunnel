# 🖥️ Como visualizar e exportar os slides (`slides.md`)

Os slides estão em [slides.md](slides.md), escritos no formato **Marp**
(Markdown → apresentação). Você tem 3 formas de vê-los. A **opção 1** é a mais
fácil para você, que já usa o VS Code.

---

## Opção 1 — VS Code (recomendado, com preview ao vivo)

1. No VS Code, abra a aba de **Extensões** (`Ctrl+Shift+X`).
2. Procure por **"Marp for VS Code"** (autor: *marp-team*) e instale.
3. Abra o arquivo [slides.md](slides.md).
4. Clique no ícone de **preview** no canto superior direito (uma lupa/tela)
   ou aperte `Ctrl+Shift+V`. Os slides aparecem do lado, atualizando enquanto
   você edita.
5. Para **exportar**: clique nos `...` (canto superior direito do editor) →
   **"Export slide deck..."** → escolha **PDF**, **PPTX** (PowerPoint) ou
   **HTML**.

> 💡 O PPTX é útil se você precisar apresentar pelo PowerPoint/Google Slides.
> O PDF é ótimo para entregar/imprimir.

---

## Opção 2 — Linha de comando (sem instalar nada permanente)

Você tem o `npx` disponível. Na raiz do projeto, rode **um** destes:

```bash
# Gera um HTML navegável (abra no navegador)
npx --yes @marp-team/marp-cli docs/slides.md -o docs/slides.html

# Gera um PDF
npx --yes @marp-team/marp-cli docs/slides.md --pdf -o docs/slides.pdf

# Gera um PowerPoint (.pptx)
npx --yes @marp-team/marp-cli docs/slides.md --pptx -o docs/slides.pptx
```

> O `npx --yes` baixa a ferramenta na hora (precisa de internet) e a executa,
> sem deixar nada instalado. O PDF/PPTX usa um Chrome headless por baixo; se der
> erro de Chrome, prefira a Opção 1.

Modo "apresentação ao vivo" no navegador (recarrega ao salvar):

```bash
npx --yes @marp-team/marp-cli -s docs/
# abra http://localhost:8080 no navegador
```

---

## Opção 3 — Site oficial (zero instalação)

Acesse **https://web.marp.app**, e cole o conteúdo de `slides.md`.
Dá para visualizar e exportar PDF direto do navegador.

---

## Como navegar na apresentação (HTML/preview)

- **→ / Espaço**: próximo slide
- **←**: slide anterior
- **F**: tela cheia (no HTML exportado)

---

## "Como o Marp sabe que é uma apresentação?"

Pelo cabeçalho no topo do `slides.md` (o bloco entre `---`):

```yaml
---
marp: true        # liga o modo apresentação
theme: gaia       # o tema visual (cores/fontes)
paginate: true    # numera os slides
---
```

E **cada `---`** no meio do arquivo separa um slide do próximo. Só isso: o resto
é Markdown normal (títulos, listas, tabelas, blocos de código). Editar um slide
é tão simples quanto editar texto.
