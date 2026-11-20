# Automação da tela: assinar documento

Como clicar em **Assinar Documento(s)** no SAD Assinador rodando no Linux,
por automação (xdotool / linux-control), e o que verificar em cada etapa.

Testado em: SAD 1.4.1, GNOME/X11, tela 1920x1080, sem escala (HiDPI 100%).

## Geometria da janela

O conteúdo JavaFX é 1024x720 (igual ao FXML) e fica 1:1 na tela. A origem
do conteúdo **não** é o canto do frame — tem a barra de título do mutter.

```bash
xwininfo -id <id-da-janela> | grep -E "Absolute|Width|Height"
```

No teste: cliente em **(124, 210)**, 1024x720. Logo:

```
tela_x = 124 + scene_x
tela_y = 210 + scene_y
```

Coordenadas vindas do FXML (`br/gov/go/detran/sad/view/DocumentosAssinatura.fxml`):

| Elemento | layoutX | layoutY | tamanho | Centro na tela |
|----------|--------:|--------:|---------|----------------|
| `assinar` (Assinar Documento(s)) | 412 | 648 | 200x33 | **(636, 872)** |
| `sair` (Sair) | 861 | 648 | 94x34 | (1032, 875) |
| `carimbo` (Adicionar Carimbo) | — | — | — | ~(775, 870) |
| `comboSituacao` | 756 | 69 | 237x46 | (998, 302) |

> Se a janela for movida, some a diferença de posição. Se o usuário mudar a
> escala de tela do GNOME, as coordenadas mudam — recalcule com `xwininfo`.

## Procedimento

1. **Focar a janela do app** (`br.gov.go.detran.sad.MainApp`, título
   "Assinador Digital - Detran GO").
2. **Marcar o documento na tabela**: clicar na coluna de seleção da linha
   (primeira coluna, checkbox). O cabeçalho é "selecionar todos".
3. **Clicar em Assinar Documento(s)** — centro em (636, 872).
4. O app **desabilita os botões** e mostra a barra de progresso enquanto
   assina (contra o backend do SAD). Aguarde alguns segundos.
5. Aparece um diálogo **"Assinatura(s) Realizada(s) N"** → clicar em **OK**.
6. A lista de pendentes passa a mostrar **"Nenhum resultado encontrado."**
   (o documento saiu de "Pendente").

Comandos equivalentes:

```bash
WID=$(xdotool search --name "Assinador Digital - Detran GO" | head -1)
xdotool windowactivate "$WID"

# clique "humano" (ver pegadinha do overlay abaixo)
click() { xdotool mousemove "$1" "$2"; sleep 0.2; xdotool mousedown 1; sleep 0.12; xdotool mouseup 1; }

click 201 486     # checkbox da linha do documento
click 636 872     # Assinar Documento(s)
```

## Pegadinha: overlay invisível engolindo os cliques

**Sintoma**: a janela responde (jstack mostra a *JavaFX Application Thread*
em `RUNNABLE` no `GtkApplication._runLoop`, ou seja, o app está saudável),
o botão parece habilitado, mas nada acontece — e nem o dropdown do
"Situação" abre.

**Causa**: o `linux-control-mcp` sobe um helper de overlay
(`~/.local/share/linux-control-mcp/python-helpers/overlay.py`) que cria uma
janela **override-redirect de 1920x1080** ("Overlay Animation System")
por cima de tudo e intercepta o mouse.

```bash
xwininfo -root -children | grep -i overlay
ps aux | grep overlay.py | grep -v grep
```

**Solução**: matar o helper e clicar com xdotool (que não recria o overlay):

```bash
pkill -f "linux-control-mcp/python-helpers/overlay.py"
```

Se voltar a travar, repita. Alternativa: usar as ferramentas de clique do
MCP, mas matando o overlay antes de cada clique.

## Diagnóstico rápido (sem tentativa e erro)

```bash
# 1. o app está vivo? (FX thread RUNNABLE = ok)
jstack <pid> | grep -A3 "JavaFX Application Thread"

# 2. qual janela está no topo no ponto do clique?
xprop -root _NET_CLIENT_LIST_STACKING   # último id = mais acima

# 3. o clique chegou? abra o combo "Situação" (998,302);
#    se o dropdown abre, o mouse está chegando no app
```

## Por que o clique "não faz nada" também pode ser regra de negócio

`DocumentosAssinaturaController.assinarDocumentos()`:

```java
List<Documentos> docs = map.entrySet().stream()
        .filter(e -> e.getValue().get())   // checkbox marcado
        .map(Map.Entry::getKey).collect(toList());
if (docs.isEmpty()) { alertShow("Nenhum Documento Selecionado."); return; }
desativaBotoes(true);                      // cinza + progresso
taskAssinarMultiplos(docs);                // thread de assinatura
```

Ou seja: se nenhuma linha estiver marcada, aparece o alerta **"Nenhum
Documento Selecionado."** e nada mais acontece — não é travamento.
