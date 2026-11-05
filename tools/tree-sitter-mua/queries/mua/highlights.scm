; GPL-3.0-or-later. See ../../../../COPYING.
(identifier) @variable
(comment) @comment
(string) @string
(escape_sequence) @string.escape
(number) @number
(boolean) @boolean
(nil) @constant.builtin

["local" "with" "define" "goto"] @keyword
["do" "function" "end" "endall"] @keyword.function
; a trailing colon opens a block as `do(..)` does (`f x:`), and `end` closes it
(lambda ":" @keyword.function)
["if" "then" "elseif" "else"] @keyword.conditional
["for" "in" "while" "repeat" "until" "break" "continue"] @keyword.repeat
"return" @keyword.return
["and" "or" "not"] @keyword.operator
["+" "-" "*" "/" "%" "^" "#" ".." "..." "==" "~=" "<" ">" "<=" ">=" "="] @operator
["(" ")" "[" "]" "{" "}"] @punctuation.bracket
["," ";" ":" "." "::"] @punctuation.delimiter

(type_annotation (identifier) @type)
(type_call (identifier) @type)
(type_member (identifier) @type)
(type_application (identifier) @type)
(parameter (identifier) @variable.parameter)
(member_expression member: (identifier) @variable.member)
(header_member member: (identifier) @variable.member)
(field (identifier) @variable.member ["=" ":"])
(field (identifier) ":" (identifier) @type)
(function_name (identifier) @function)
(handler name: (identifier) @function)
(call_expression function: (identifier) @function.call)
(call_expression function: (member_expression member: (identifier) @function.call))
(call_expression method: (identifier) @function.method.call)
(expression_statement (identifier) @function.call)
(expression_statement (member_expression member: (identifier) @function.call))
(bare_method_call method: (identifier) @function.method.call)
(header_call function: (identifier) @function.call)
(header_call method: (identifier) @function.method.call)
(local_declaration (binding name: (identifier) @function) "=" (lambda))

; Mua's own forms and checkers, by spelling (not semantic resolution)
((identifier) @keyword
 (#any-of? @keyword "struct" "oneof" "ffistruct" "closed" "required" "optional"))
((identifier) @type.builtin
 (#any-of? @type.builtin "Number" "String" "Boolean" "Table" "Function" "Any" "Unit" "Optional"))
