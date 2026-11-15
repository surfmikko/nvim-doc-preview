# Records doc/demo.gif. Run from the repo root: make demo (needs vhs).
# Syntax: https://github.com/charmbracelet/vhs
Output doc/demo.gif

Set Shell "bash"
Set FontSize 16
Set Width 1200
Set Height 720
Set Padding 12
Set Theme "Dracula"
Set TypingSpeed 30ms
Set PlaybackSpeed 1

Type "nvim -u tools/demo/init.lua -i NONE --noplugin doc/sample-markdown-demo.md"
Sleep 400ms
Enter
Sleep 2s

# replace: the preview takes over the source window
Type ":DocPreview toggle replace"
Sleep 400ms
Enter
Sleep 2s
Ctrl+D
Sleep 1s
Ctrl+D
Sleep 1s
Ctrl+U
Sleep 700ms
Ctrl+U
Sleep 1s
Type ":DocPreview toggle"
Sleep 400ms
Enter
Sleep 1400ms

# vsplit: preview to the right, scrolling stays in sync
Type ":DocPreview toggle vsplit"
Sleep 400ms
Enter
Sleep 2s
Ctrl+D
Sleep 1s
Ctrl+D
Sleep 1s
Ctrl+U
Sleep 700ms
Ctrl+U
Sleep 1s
Type ":DocPreview toggle"
Sleep 400ms
Enter
Sleep 1400ms

# hsplit: preview below
Type ":DocPreview toggle hsplit"
Sleep 400ms
Enter
Sleep 2s
Ctrl+D
Sleep 1s
Ctrl+D
Sleep 1s
Ctrl+U
Sleep 700ms
Ctrl+U
Sleep 1s
Type ":DocPreview toggle"
Sleep 400ms
Enter
Sleep 1400ms

Type ":q"
Sleep 400ms
Enter
Sleep 1s
