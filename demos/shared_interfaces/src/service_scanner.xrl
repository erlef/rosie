
Definitions.

Rules.

int64 : {token, {type, int64}}. % TokenLine for line
[\-]+ : {token, {separator}}.
[a-z]+ : {token, {name, TokenChars}}.
[\s\t\n]+ : skip_token.
[.]+ : {error, syntax}.

Erlang code.
