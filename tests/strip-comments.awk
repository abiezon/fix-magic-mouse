# strip-comments.awk — remove C comments from a source file, keeping line numbering.
#
# The source-guarantee tests assert things like "this program makes no network calls" by
# grepping for call syntax. Run against the raw file those greps also read the prose:
# a comment saying the mouse "pairs, connects and reports battery" looks exactly like a
# connect() call. Stripping comments first is what makes the assertion mean something.
#
# Deliberately simple: it does not track string literals, so a "//" inside a string would
# truncate that line. There is none in this project, and a test that silently passed on a
# mis-stripped line would be worse than one that visibly failed.

BEGIN { in_block = 0 }
{
    line = $0; out = ""; i = 1; n = length(line)
    while (i <= n) {
        one = substr(line, i, 1)
        two = substr(line, i, 2)
        if (in_block) {
            if (two == "*/") { in_block = 0; i += 2 } else { i++ }
        } else {
            if      (two == "/*") { in_block = 1; i += 2 }
            else if (two == "//") { break }
            else                  { out = out one; i++ }
        }
    }
    print out
}
