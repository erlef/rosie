Nonterminals service reply request element elements.

Terminals type name separator.

Rootsymbol service.

element -> type name : {'$1','$2'}.
elements -> element : ['$1'].
elements -> element elements : ['$1'] ++ '$2'.
request -> elements : '$1'.
reply -> separator elements : '$2'.

service -> request reply : {'$1', '$2'}.

Erlang code.
