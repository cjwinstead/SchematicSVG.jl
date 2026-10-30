# ─────────────────────────── netlist extraction ─────────────────────
#
# Connectivity comes from geometry: wire vertices, device pins and markers (grounds,
# supplies, terminals, node tags) that coincide are one node, and a point lying inside a
# wire segment joins that wire (a T-junction). Two wires that merely cross are not joined.
#
# Values come, in order of preference, from `elements` passed here, from the elements
# given when the schematic was annotated (kept in `s.values`), and finally from the text
# in the drawing ("4.7 kΩ", "R_1 = 10k", a model name in the note).

"""
    NetDevice(name, kind, nodes, value)

One device of a [`SchematicNetlist`](@ref). `kind` is one of
`:R :C :L :D :V :I :sV :sI :E :F :G :H :nmos :pmos :npn :pnp :opamp` and `nodes` are in
SPICE order: (n+, n−) for two-terminal parts and sources, (anode, cathode) for diodes,
(drain, gate, source), (collector, base, emitter), and (+, −, out) for op-amps. `value`
is whatever was supplied for the device (a number, string, symbol, tuple, NamedTuple or
an element object), or what could be read from the drawing, or `nothing`.
"""
struct NetDevice
    name::String
    kind::Symbol
    nodes::Vector{String}
    value::Any
end

"""
    SchematicNetlist

Result of [`schematic_netlist`](@ref): `devices` (a vector of [`NetDevice`](@ref)),
`supplies` (supply net => value, `nothing` when not given) and `nets` (all node names;
ground is `"0"`). Displays as SPICE text.
"""
struct SchematicNetlist
    devices::Vector{NetDevice}
    supplies::Vector{Pair{String,Any}}
    nets::Vector{String}
end

# ─────────────── geometry → nodes ───────────────

const NETTOL = 1e-6
netkey(p::Pt) = (round(Int, p.x / NETTOL), round(Int, p.y / NETTOL))

function netroot!(parent, k)
    p = get!(parent, k, k)
    p == k && return k
    r = netroot!(parent, p)
    parent[k] = r
    r
end
netjoin!(parent, a, b) = (ra = netroot!(parent, a); rb = netroot!(parent, b); ra != rb && (parent[ra] = rb))

# Strictly inside segment a–b (not at an end)?
function inside(t::Pt, a::Pt, b::Pt)
    d = b - a
    L2 = d.x^2 + d.y^2
    L2 == 0 && return false
    v = t - a
    abs(v.x * d.y - v.y * d.x) > NETTOL * sqrt(L2) && return false
    u = (v.x * d.x + v.y * d.y) / L2
    NETTOL < u < 1 - NETTOL
end

# Pins of each device kind, in SPICE order.
devicepins(b::Bipole) = [b.a, b.b]
devicepins(t::Transistor) = t.kind in (:nmos, :pmos) ? [pin(t, :D), pin(t, :G), pin(t, :S)] :
                                                       [pin(t, :C), pin(t, :B), pin(t, :E)]
devicepins(o::Opamp) = [pin(o, :inp), pin(o, :inn), pin(o, :out)]

# ─────────────── values from the drawing ───────────────

const SIPREFIX = Dict("f" => 1e-15, "p" => 1e-12, "n" => 1e-9, "u" => 1e-6, "µ" => 1e-6,
                      "μ" => 1e-6, "m" => 1e-3, "k" => 1e3, "K" => 1e3, "M" => 1e6,
                      "meg" => 1e6, "Meg" => 1e6, "MEG" => 1e6, "G" => 1e9, "T" => 1e12)
const VALUE_RX = r"^([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)\s*(meg|Meg|MEG|[fpnuµμmkKMGT])?\s*(Ω|ohms?|Ohms?|F|H|V|A|S|Hz|W)?$"

# Plain text from label syntax: "$R_1 = 10\,k\Omega$" → "R1 = 10 kΩ".
function plaintext(s::AbstractString)
    s = replace(s, "\$" => "")
    s = replace(s, r"\\(?:mathrm|text|textrm|mbox)\{([^}]*)\}" => s"\1")
    s = replace(s, r"\\([A-Za-z]+) ?" => m -> get(TEXMACROS, rstrip(m[2:end]), ""))
    for (k, v) in ("\\," => " ", "\\;" => " ", "\\_" => "\x01", "_" => "", "{" => "", "}" => "", "\x01" => "_")
        s = replace(s, k => v)
    end
    strip(s)
end

"""
    parse_value(text) -> Float64 or nothing

Read an engineering value such as "4.7 kΩ", "10µF", "2.2n", "1e3" or "5 V". Prefixes are
SI (M is mega, m is milli; "meg" also works). Returns `nothing` if `text` isn't a value.
"""
function parse_value(text::AbstractString)
    m = match(VALUE_RX, strip(text))
    m === nothing && return nothing
    x = parse(Float64, m[1])
    m[2] === nothing ? x : round(x * SIPREFIX[m[2]]; sigdigits=12)   # 10µ is 1e-5, not 9.99…e-6
end

# Value and model text written in the drawing (note first, then "name = value" labels).
function drawnvalue(label::AbstractString, note::AbstractString, wantmodel::Bool)
    n = plaintext(note)
    l = plaintext(label)
    tail = occursin('=', l) ? strip(split(l, '='; limit=2)[2]) :
           occursin(':', l) ? strip(split(l, ':'; limit=2)[2]) : ""
    if wantmodel
        !isempty(n) && return String(n)
        !isempty(tail) && return String(tail)
        return nothing
    end
    for t in (n, tail, l)
        isempty(t) && continue
        v = parse_value(t)
        v === nothing || return v
    end
    isempty(n) ? nothing : String(n)          # e.g. "SIN(0 1 1k)" or "{Rload}"
end

# A raw value supplied for a device: element objects with name/value/model fields are
# reduced to that value here (package extensions keep their own objects).
rawvalue(x::Union{Nothing,Number,AbstractString,Symbol,Tuple,NamedTuple,AbstractVector}) = x
rawvalue(x) = (hasproperty(x, :name) && (hasproperty(x, :value) || hasproperty(x, :model))) ?
              annotation(x) : x

# (gain, control) of a dependent source, or nothing.
function controlspec(v)
    v isa Tuple && length(v) == 2 && return (v[1], v[2])
    v isa NamedTuple && haskey(v, :gain) && haskey(v, :control) && return (v.gain, v.control)
    if !(v isa Union{Nothing,Number,AbstractString,Symbol,Tuple,NamedTuple,AbstractVector}) &&
       hasproperty(v, :gain) && hasproperty(v, :control)
        return (getproperty(v, :gain), getproperty(v, :control))
    end
    nothing
end
iscurrentcontrol(c) = c isa Union{AbstractString,Symbol}

# ─────────────── extraction ───────────────

"""
    schematic_netlist(s::Schematic; elements=(), supplies=Dict()) -> SchematicNetlist

Extract the circuit drawn in `s`: devices with their nodes in SPICE order, and node
names. Ground symbols are node `"0"`; supply symbols, terminals and `@` node tags name
their nodes (`vdd`, `vin`, …); other nodes are numbered `n1`, `n2`, ….

Device values are looked up by instance name (case-insensitive) in `elements` (a
collection of element objects or a `name => value` dictionary, as for
[`annotate`](@ref)), then in the elements the schematic was annotated with, and finally
read from the drawing's text. For dependent sources give `(gain, control)`: a pair of
node names for E/G sources, a voltage-source name for H/F sources. `supplies` gives the
voltage of each supply net, e.g. `Dict("vdd" => 5)`.

`rename` maps drawn node names to netlist names, e.g. `Dict("vdd" => "vdd!")` for global
nodes. `external` lists nodes connected outside the drawing (subcircuit terminals, global
supplies): they count as driven for the DC check and need no supply voltage.

Warns about devices without a value, unconnected pins, nodes with conflicting names, and
nodes with no DC path to ground.
"""
function schematic_netlist(s::Schematic; elements=(), supplies=Dict(), external=(), rename=Dict())
    renames = Dict{String,String}(lowercase(string(k)) => string(v) for (k, v) in rename)
    rn(n) = get(renames, lowercase(n), n)
    externals = Set{String}()
    for x in external
        push!(externals, lowercase(string(x)), lowercase(rn(string(x))))
    end
    vals = copy(s.values)
    if elements isa AbstractDict
        for (k, v) in elements
            vals[uppercase(string(k))] = v
        end
    else
        for e in elements
            vals[uppercase(instancename(e))] = e
        end
    end
    devs = Dict{String,Placed}(t.name => t for t in s.items if t isa Union{Transistor,Opamp})
    resolvept(p) = p isa PinRef ? pin(devs[p.device], p.pin) : p

    # 1. Segments (wires and shorts) and every point that can carry a connection.
    segs = Tuple{Pt,Pt}[]
    pts = Pt[]
    for it in s.items
        if it isa Wire
            ps = map(resolvept, it.pts)
            append!(pts, ps)
            for i in 1:length(ps)-1
                push!(segs, (ps[i], ps[i+1]))
            end
        elseif it isa Bipole && it.kind == :short
            push!(segs, (it.a, it.b)); push!(pts, it.a, it.b)
        elseif it isa Union{Bipole,Transistor,Opamp}
            append!(pts, devicepins(it))
        elseif it isa Union{Ground,Supply,Port,NodeLabel,Dot}
            push!(pts, it.at)
        end
    end
    parent = Dict{Tuple{Int,Int},Tuple{Int,Int}}()
    for p in pts
        netroot!(parent, netkey(p))
    end
    for (a, b) in segs
        netjoin!(parent, netkey(a), netkey(b))
    end
    for p in pts, (a, b) in segs                         # T-junctions
        inside(p, a, b) && netjoin!(parent, netkey(p), netkey(a))
    end
    root(p) = netroot!(parent, netkey(p))

    # 2. Node names: ground > supplies > terminals and node tags.
    named = Dict{Tuple{Int,Int},Tuple{Int,String}}()       # root => (priority, name)
    supplynets = String[]
    function name!(p, prio, nm)
        isempty(nm) && return
        r = root(p)
        old = get(named, r, nothing)
        if old === nothing || prio < old[1]
            named[r] = (prio, nm)
        elseif old[2] != nm && prio == old[1] && prio > 0
            @warn "schematic_netlist: node has two names, '$(old[2])' and '$nm'; using '$(old[2])'"
        end
    end
    for it in s.items
        if it isa Ground
            name!(it.at, 0, "0")
        elseif it isa Supply
            nm = supplyname(it)
            name!(it.at, 1, nm)
            nm in supplynets || push!(supplynets, nm)
        elseif it isa Union{Port,NodeLabel}
            name!(it.at, 2, it.name)
        end
    end
    used = Set(lowercase(n) for (_, n) in values(named))
    auto = Dict{Tuple{Int,Int},String}()
    k = 0
    netname(p) = rn(rawnetname(p))
    function rawnetname(p)
        r = root(p)
        haskey(named, r) && return named[r][2]
        get!(auto, r) do
            nm = ""
            while true
                k += 1
                nm = "n$k"
                lowercase(nm) in used || break
            end
            nm
        end
    end

    # 3. Devices.
    pincount = Dict{Tuple{Int,Int},Int}()
    for it in s.items
        it isa Union{Bipole,Transistor,Opamp} || continue
        it isa Bipole && it.kind in (:short, :open) && continue
        for p in devicepins(it)
            pincount[root(p)] = get(pincount, root(p), 0) + 1
        end
    end
    devices = NetDevice[]
    taken = Set{String}()
    counters = Dict{Char,Int}()
    missingvalue = String[]
    for it in s.items
        it isa Union{Bipole,Transistor,Opamp} || continue
        if it isa Bipole
            it.kind in (:short, :open) && continue
            if it.kind == :box
                @warn "schematic_netlist: '$(isempty(it.name) ? it.label : it.name)' is an unknown element; left out of the netlist"
                continue
            end
        end
        name = it.name
        vkey = lookupname(vals, it)
        raw = vkey === nothing ? nothing : vals[vkey]
        v = raw === nothing ? nothing : rawvalue(raw)
        letter0 = isempty(name) ? ' ' : uppercase(name[1])
        kind = if it isa Transistor
            it.kind
        elseif it isa Opamp
            :opamp
        elseif it.kind == :sV
            letter0 == 'I' ? :sI : :sV
        elseif it.kind == :cV
            letter0 in ('E', 'H') ? Symbol(letter0) :
            (c = controlspec(raw); c !== nothing && iscurrentcontrol(c[2])) ? :H : :E
        elseif it.kind == :cI
            letter0 in ('F', 'G') ? Symbol(letter0) :
            (c = controlspec(raw); c !== nothing && iscurrentcontrol(c[2])) ? :F : :G
        else
            it.kind
        end
        if raw === nothing                                   # read it from the drawing
            v = drawnvalue(it.label, it.note, kind in (:D, :nmos, :pmos, :npn, :pnp, :opamp))
            v === nothing && kind in (:R, :C, :L, :V, :I, :E, :F, :G, :H) && push!(missingvalue, name)
        end
        if kind in (:E, :F, :G, :H) && controlspec(raw) === nothing
            throw(ArgumentError("dependent source $(isempty(name) ? "(unnamed)" : name) needs " *
                "(gain, control) in `elements`: a pair of node names for E/G, " *
                "a voltage-source name for H/F, e.g. \"$name\" => (2e-3, (\"vx\", \"0\"))"))
        end
        # Instance names: unique, auto-numbered when the drawing has none.
        if isempty(name) || uppercase(name) in taken
            isempty(name) || @warn "schematic_netlist: duplicate instance name $name; renaming"
            letter = SPICE_LETTER[kind]
            while true
                counters[letter] = get(counters, letter, 0) + 1
                name = string(letter, counters[letter])
                uppercase(name) in taken || haskey(vals, uppercase(name)) || break
            end
        end
        push!(taken, uppercase(name))
        nodes = [netname(p) for p in devicepins(it)]
        for (p, nd) in zip(devicepins(it), nodes)
            get(pincount, root(p), 0) == 1 && !haskey(named, root(p)) &&
                @warn "schematic_netlist: pin of $name at node $nd is not connected to anything"
        end
        push!(devices, NetDevice(name, kind, nodes, raw === nothing ? v : raw))
    end
    isempty(missingvalue) ||
        @warn "schematic_netlist: no value for $(join(missingvalue, ", ")); written as parameters {name}"

    # 4. Nodes SPICE can't solve at DC.
    autonames = Set([rn(x) for x in values(auto)])
    if !isempty(devices) && !any(it -> it isa Ground, s.items)
        @warn "schematic_netlist: the schematic has no ground symbol; SPICE needs a node 0 (draw a gnd)"
    else
        driven = unique!(vcat(rn.(supplynets),
                              [n for d in devices for n in d.nodes if lowercase(n) in externals]))
        groups, highz = dc_floating_groups(devices, driven)
        for g in groups
            at = something(findfirst(n -> !(n in autonames), g), 1)    # prefer a named node
            node = g[at]
            what = length(g) == 1 ? "node $node has" : "nodes $(join(g, ", ")) have"
            fix = node in highz ?
                "Add a bias resistor between $node and ground (or a supply)." :
                "Add a load resistor between $node and ground."
            @warn "schematic_netlist: $what no DC path to ground, so SPICE can't find the " *
                  "operating point (it connects only through capacitors, current sources or " *
                  "high-impedance inputs). $fix"
        end
    end

    supplyvals = Dict(lowercase(string(k)) => v for (k, v) in supplies)
    sup = Pair{String,Any}[rn(n) => get(supplyvals, n, get(supplyvals, lowercase(rn(n)), nothing))
                           for n in supplynets if !(n in externals)]
    nosource = [n for (n, v) in sup if v === nothing]
    isempty(nosource) ||
        @warn "schematic_netlist: no voltage for supply $(join(nosource, ", ")); pass supplies=Dict(\"$(first(nosource))\" => …)"
    nets = unique!([rn(x) for x in vcat([named[r][2] for r in keys(named)], collect(values(auto)))])
    SchematicNetlist(devices, sup, sort!(nets))
end

"""
    dc_floating_groups(devices, supplynets) -> (groups, highz)

Nodes with no DC path to ground, grouped by the islands they form, and the set of nodes
that touch a high-impedance input. Conducting at DC: resistors, inductors, diodes,
voltage sources (also controlled ones' outputs), a MOSFET's drain–source channel, all
BJT terminals, and an op-amp output (the library models drive it from ground). Not
conducting: capacitors, current sources, MOSFET gates and op-amp inputs. Supply nets are
driven by sources to ground.
"""
function dc_floating_groups(devices::Vector{NetDevice}, supplynets)
    parent = Dict{String,String}()
    function r(x)
        p = get!(parent, x, x)
        p == x && return x
        q = r(p)
        parent[x] = q
        q
    end
    j(a, b) = (ra = r(a); rb = r(b); ra != rb && (parent[ra] = rb))
    r("0")
    foreach(n -> j(n, "0"), supplynets)
    highz = Set{String}()
    order = String[]
    for d in devices
        for n in d.nodes
            haskey(parent, n) || push!(order, n)
            r(n)
        end
        k, n = d.kind, d.nodes
        if k in (:R, :L, :D, :V, :sV, :E, :H)
            j(n[1], n[2])
        elseif k in (:nmos, :pmos)
            j(n[1], n[3]); push!(highz, n[2])
        elseif k in (:npn, :pnp)
            j(n[1], n[2]); j(n[2], n[3])
        elseif k == :opamp
            j(n[3], "0"); push!(highz, n[1], n[2])
        end
    end
    groups = Dict{String,Vector{String}}()
    roots = String[]
    for n in order
        n == "0" && continue
        rt = r(n)
        rt == r("0") && continue
        haskey(groups, rt) || push!(roots, rt)
        push!(get!(groups, rt, String[]), n)
    end
    [groups[rt] for rt in roots], highz
end

const SPICE_LETTER = Dict(:R => 'R', :C => 'C', :L => 'L', :D => 'D', :V => 'V', :I => 'I',
                          :sV => 'V', :sI => 'I', :E => 'E', :F => 'F', :G => 'G', :H => 'H',
                          :nmos => 'M', :pmos => 'M', :npn => 'Q', :pnp => 'Q', :opamp => 'X')

# Default models, as in the Microelectronics.jl model library.
const DEFAULT_MODEL = Dict(:D => "D1N914", :nmos => "ald1105n", :pmos => "ald1105p",
                           :npn => "Q2N3904", :pnp => "Q2N3906", :opamp => "ideal_opamp")

"SPICE instance name: the drawn name, with the device letter prepended if it is missing."
spicename(name::AbstractString, letter::Char) =
    !isempty(name) && uppercase(name[1]) == letter ? String(name) : string(letter, name)

# ─────────────── SPICE text ───────────────

spicevalue(x::Integer) = string(x)
function spicevalue(x::AbstractFloat)
    y = round(x; sigdigits=12)
    isinteger(y) && abs(y) < 1e15 ? string(Int(y)) : string(y)
end
spicevalue(x::Symbol) = "{$x}"
spicevalue(x::AbstractString) = String(x)
spicevalue(x) = string(x)
# Unitful quantities are handled by package extensions (plain SI numbers, or
# Microelectronics' qstr when it is loaded), so "20 kΩ" never reaches a netlist.

# Hook for package extensions: SPICE text for a device given as an element object.
objectline(x, d::NetDevice) = nothing

function spiceline(d::NetDevice)
    line = objectline(d.value, d)
    line === nothing || return line
    letter = SPICE_LETTER[d.kind]
    nm = spicename(d.name, letter)
    v = rawvalue(d.value)
    nodes = join(d.nodes, " ")
    if d.kind in (:R, :C, :L)
        return "$nm $nodes $(v === nothing ? "{$nm}" : spicevalue(v))"
    elseif d.kind in (:V, :I)
        v === nothing && return "$nm $nodes DC {$nm}"
        return v isa AbstractString ? "$nm $nodes $v" : "$nm $nodes DC $(spicevalue(v))"
    elseif d.kind in (:sV, :sI)
        v isa AbstractString && return "$nm $nodes $v"
        p = v isa NamedTuple ? v : v === nothing ? NamedTuple() : (amplitude=v,)
        g(k, dflt) = spicevalue(get(p, k, dflt))
        return "$nm $nodes SIN($(g(:offset, 0)) $(g(:amplitude, 5e-3)) $(g(:frequency, 1000)))"
    elseif d.kind in (:E, :F, :G, :H)
        gain, ctrl = controlspec(d.value)
        c = iscurrentcontrol(ctrl) ? string(ctrl) : join(string.(collect(ctrl)), " ")
        return "$nm $nodes $c $(spicevalue(gain))"
    elseif d.kind == :D
        return "$nm $nodes $(v isa AbstractString ? v : DEFAULT_MODEL[:D])"
    elseif d.kind in (:nmos, :pmos)
        model = v isa AbstractString ? v : v isa NamedTuple && haskey(v, :model) ? v.model : DEFAULT_MODEL[d.kind]
        params = v isa NamedTuple ? join([" $(uppercase(string(k)))=$(spicevalue(x))" for (k, x) in pairs(v) if k != :model]) : ""
        return "$nm $nodes $(d.nodes[3]) $model$params"          # body tied to source
    elseif d.kind in (:npn, :pnp)
        return "$nm $nodes $(v isa AbstractString ? v : DEFAULT_MODEL[d.kind])"
    else                                                         # :opamp subcircuit
        return "$nm $nodes $(v isa AbstractString ? v : DEFAULT_MODEL[:opamp])"
    end
end

function Base.print(io::IO, n::SchematicNetlist)
    for (net, v) in n.supplies
        nm = spicename(uppercase(net), 'V')
        println(io, "$nm $net 0 DC $(v === nothing ? "{$nm}" : spicevalue(v))")
    end
    for d in n.devices
        println(io, spiceline(d))
    end
end
Base.show(io::IO, ::MIME"text/plain", n::SchematicNetlist) = print(io, n)

"""
    spice_netlist(s::Schematic; title="schematic", include=nothing, elements=(), supplies=Dict()) -> String

SPICE text for the circuit drawn in `s` (see [`schematic_netlist`](@ref)), with a title
line, an optional `.include` and `.end`. Values without units are written as plain
numbers; devices without a value get a `{name}` parameter, and parts without a model use
the Microelectronics.jl library defaults (D1N914, ald1105n/p, Q2N3904/6, ideal_opamp).
"""
function spice_netlist(s::Schematic; title="schematic", include=nothing, kw...)
    io = IOBuffer()
    println(io, "* ", title)
    include === nothing || println(io, ".include ", include)
    print(io, schematic_netlist(s; kw...))
    println(io, ".end")
    String(take!(io))
end

# Node name a supply symbol stands for: "V_{DD}" → "vdd".
function supplyname(u::Supply)
    nm = lowercase(name_from_label(u.label))
    isempty(nm) ? (u.up ? "vdd" : "vss") : nm
end
"Names of the supply nodes drawn in `s` (`vdd`, `vss`, …)."
supplynames(s::Schematic) = unique!([supplyname(u) for u in s.items if u isa Supply])

paramtext(p::Pair) = "$(first(p))=$(spicevalue(last(p)))"
paramtext(p) = "$(p.name)=$(spicevalue(p.value))"

"""
    spice_subcircuit(s::Schematic; name, terminals, params=(), rename=Dict(), elements=()) -> String

A `.subckt name terminals… params: …` … `.ends` block for the circuit drawn in `s`.
`terminals` are drawn node names (e.g. `["in", "out"]`); supply nodes are left to the
enclosing netlist, so use `rename` to make them global (`Dict("vdd" => "vdd!")`, with
`.global vdd!` in the netlist). `params` are `name => default` pairs that device values
can refer to as symbols (`:Rload` is written `{Rload}`).
"""
function spice_subcircuit(s::Schematic; name, terminals, params=(), rename=Dict(), elements=())
    n = subcircuit_netlist(s, terminals; rename, elements)
    renames = Dict(lowercase(string(k)) => string(v) for (k, v) in rename)
    io = IOBuffer()
    print(io, ".subckt ", name, " ", join([get(renames, lowercase(string(t)), string(t)) for t in terminals], " "))
    isempty(params) || print(io, " params: ", join(paramtext.(collect(params)), " "))
    println(io)
    for d in n.devices
        println(io, spiceline(d))
    end
    println(io, ".ends ", name)
    String(take!(io))
end

# The netlist of a subcircuit: terminals and supplies are external, and every terminal
# must be a node of the drawing.
function subcircuit_netlist(s::Schematic, terminals; rename=Dict(), elements=())
    ext = vcat([string(t) for t in terminals], supplynames(s))
    n = schematic_netlist(s; elements, rename, external=ext)
    renames = Dict(lowercase(string(k)) => string(v) for (k, v) in rename)
    for t in terminals
        tn = get(renames, lowercase(string(t)), string(t))
        any(x -> lowercase(x) == lowercase(tn), n.nets) ||
            throw(ArgumentError("subcircuit terminal '$t' is not a node of the drawing (nodes: $(join(n.nets, ", ")))"))
    end
    n
end

"""
    to_subcircuit(s::Schematic; name, terminals, parameters=[], rename=Dict(), elements=())

A Microelectronics.jl `Subcircuit` for the circuit drawn in `s`, with the given
`terminals` (drawn node names); see [`spice_subcircuit`](@ref) for `rename` and
parameters. Available after `using Microelectronics`.
"""
function to_subcircuit end

"""
    to_microelectronics(s::Schematic; elements=(), supplies=Dict()) -> (; sources, components)

Microelectronics.jl objects for the circuit drawn in `s`, ready for
`build_netlist(; to_microelectronics(s)...)`. Available after `using Microelectronics`
(it is a package extension). Element objects you pass in `elements` (or annotated the
schematic with) are reused with the schematic's nodes, so their values, models, waveforms
and parameters carry over; other devices are built from the values found by
[`schematic_netlist`](@ref).
"""
function to_microelectronics end
