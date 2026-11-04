# Reading Mua

A tour for someone who knows Lua and meets Mua for the first time. Mua is Lua with a few
extra spellings; every one of them is written back as plain Lua before anything runs. This
page reads one small function slowly, undoes each spelling, and then explains the colon,
which is the one that looks strangest.

## A function that takes a block

```mua
local with_log =: title
    return do(body)
        print("begin " .. title)
        body
        print("end " .. title)
    end
end

with_log "import":
    print("  reading")
    print("  writing")
end
```

This prints:

```text
begin import
  reading
  writing
end import
```

`with_log` is an **activity**: it sets something up (here, a log line), runs a block of code
that the caller supplies, and completes (the closing log line). The block is the part between
`with_log "import":` and `end`.

Read on to see where each piece comes from.

## Undoing the sugar, one spelling at a time

Every block below is a complete program that prints the same four lines. `tests/tour.lua`
runs them to check it.

**1. `=: title` is `= do(title)`.** A colon right after `=` assigns a block, and the names after
it are the block's parameters. So the first line says: `with_log` is a function of `title`.

```mua
local with_log = do(title)
    return do(body)
        print("begin " .. title)
        body
        print("end " .. title)
    end
end

with_log "import":
    print("  reading")
    print("  writing")
end
```

**2. A name alone on a line is a call.** `body` as a whole statement means `body()`: calling a
function with no arguments needs no parentheses. (In an expression the name is still the
function itself: `local f = body` keeps it.)

```mua
local with_log = do(title)
    return do(body)
        print("begin " .. title)
        body()
        print("end " .. title)
    end
end

with_log "import":
    print("  reading")
    print("  writing")
end
```

**3. The call site is two applications.** In Mua, application is curried: `f a b` is
`f(a)(b)`. And a colon at the end of a line passes the block that follows as the next
argument. So `with_log "import":` followed by a block is `with_log("import")(block)`: first
give the title, getting back the function that wants a block, then give it the block. That is
why `with_log` returns a function.

```mua
local with_log = do(title)
    return do(body)
        print("begin " .. title)
        body()
        print("end " .. title)
    end
end

with_log("import")(do(..)
    print("  reading")
    print("  writing")
end)
```

**4. `do(...) ... end` is `function(...) ... end`.** A lambda is a Lua function. This is plain
Lua except for the `do(..)` of the block, which says that the block opens whatever it is given
(see below).

```mua
local with_log = function(title)
    return function(body)
        print("begin " .. title)
        body()
        print("end " .. title)
    end
end

with_log("import")(function()
    print("  reading")
    print("  writing")
end)
```

That last program is ordinary Lua. Nothing in Mua adds a runtime for any of this: the
translator only rewrites spellings.

## The colon, in its five meanings

A colon is the one character that means several things in Lua already, and Mua adds one
more. The rule that tells them apart is position.

```text
obj:method(x)            a method call: a name directly after the colon
local n: Number = 1     an annotation: a type after a name, in a declaration or parameter list
do(x: Number): Number    an annotation: the result type after a parameter list
::label::                a label, in goto
with_log "import":       a block: the colon ends the line (names may follow it)
local f =: x             a block: the colon follows `=`
```

The block colon only applies where nothing else could mean a colon: at the end of a line (after
an expression) or right after `=`. Anything after it on the same line must be parameter names.

```text
xs:each: key value       `xs:each` is a method access, then the colon ends the line: the block
                         has two parameters, `key` and `value`
tasks: scope..           the block opens its argument and calls it `scope`
spawn:                   no names: the block opens whatever it is handed
```

## What `do(..)` means

A block can **open** a table, so that its keys are names in the block. `do(ctx..)` receives
one argument and opens it as `ctx`; `do(..)` does the same without a name. A colon block
with no names is `do(..)`:

```mua
local with_config = do(body)
    body { name = "mua", mode = "tour" }
end

with_config:
    print(name, mode)
end
```

It prints `mua tour`: `name` and `mode` are the keys of the table the block was handed.
When an activity hands over nothing, the block opens nothing, and a name like `print` is
looked up as usual. That is why the real translation of the first program starts every free
name with a check of what the block opened (see the next section).

## See what a spelling means

`mua -d` prints the Lua a file translates to. For the first program:

```text
local __mua = __mua or require("mua.runtime"); local with_log = function(title)
return function(body)
print("begin " .. title);
body();
print("end " .. title);
end;
end;

with_log("import")(function(__home) local __o1n, __o1 = __mua.open(__home);
(__o1n.print ? __o1.print : print)("  reading");
(__o1n.print ? __o1.print : print)("  writing");
end);
```

The first function is step 4 above. The call site shows the block opening: `__mua.open`
records what the block was handed, and each free name in the block reads as
`(opened.name ? opened.name : name)`, a check for a key of the opened table first. It costs
nothing when the block opens nothing, and no table or closure is built for the lookup.

## A short reading table

```text
f x y                    f(x)(y)                       application is curried
f x:  ...  end           f(x)(do(..) ... end)          a trailing block is the next argument
local f =: a b  ... end  local f = do(a, b) ... end     a block assigned to a name
name                     name()                        a bare name as a statement is a call
a ? b : c                a conditional                 LuaJIT 3.0 syntax
x -> x + 1               function(x) return x + 1 end  a short function
define ... end           def with ... end              a table of names, closed by `end`
```

Next: [the syntax reference](syntax.md) for every rule, [the guide](designing-and-writing-mua.md)
for how to design with these forms, and the `examples/` directory for programs to run.
