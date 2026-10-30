using SchematicSVG
using Test
using Unitful          # loads SchematicSVGUnitfulExt

# Stand-ins for the user's element structs
struct Res; name::String; value::Float64; end
struct Fet; name::String; model::String; end

nfind(pat, s) = length(findall(pat, s))
near(a::Pt, b::Pt) = isapprox(a.x, b.x; atol=1e-9) && isapprox(a.y, b.y; atol=1e-9)
count_of(T, s::Schematic) = count(x -> x isa T, s.items)
bipoles(s::Schematic) = filter(x -> x isa Bipole, s.items)

@testset "SchematicSVG" begin

    @testset "geometry and pins" begin
        @test Pt(1, 2) + Pt(3, 4) == Pt(4, 6)
        @test 2 * Pt(1, 2) == Pt(2, 4)

        q = Transistor(:npn, "Q1", Pt(0, 0))
        @test pin(q, :B) == Pt(-0.5, 0)
        @test pin(q, :C) == Pt(0, 0.5)
        @test pin(q, :E) == Pt(0, -0.5)

        m = Transistor(:pmos, "M1", Pt(1, 1); xflip=true, yflip=true)
        @test pin(m, :G) == Pt(1.5, 1)
        @test pin(m, :S) == Pt(1, 1.5)       # source on top when flipped
        @test_throws ErrorException pin(m, :X)

        o = Opamp("OA1", Pt(0, 0))
        @test pin(o, :inp) == Pt(-0.5, 0.2)
        @test pin(o, :out) == Pt(0.5, 0)
    end

    @testset "labels" begin
        markup, n = SchematicSVG.texlabel(raw"$R_{C}$")
        @test n == 2
        @test occursin("<tspan dy=\"4\"", markup)
        @test SchematicSVG.texlabel(raw"$\beta$")[1] == "β"
        @test SchematicSVG.texlabel("a<b")[1] == "a&lt;b"
        # text after a subscript is shifted back up to the baseline
        @test occursin("<tspan dy=\"-4\">", SchematicSVG.texlabel("g_m v")[1])
    end

    @testset "SVG output" begin
        s = Schematic([
            Bipole(:V, Pt(0, 1), Pt(0, 0), raw"$v_{in}$"), Ground(Pt(0, 0)),
            Wire(Pt(0, 1), PinRef("Q1", :B)),
            Transistor(:npn, "Q1", Pt(1, 1)),
            Bipole(:R, Pt(1, 2.5), Pt(1, 1.5), "R"), Wire(Pt(1, 1.5), PinRef("Q1", :C)),
            Supply(Pt(1, 2.5), "V_{CC}", true),
            Port(Pt(2, 1), "out", :right), Dot(Pt(1, 1.5)),
        ])
        svg = to_svg(s)
        @test startswith(svg, "<svg")
        @test endswith(svg, "</svg>")
        @test occursin("polyline", svg)
        @test occursin("viewBox", svg)
        @test sprint(show, MIME("image/svg+xml"), s) == svg
        @test showable(MIME("image/svg+xml"), s)
        # every bipole kind renders
        for k in (:R, :C, :L, :D, :V, :I, :cV, :cI, :open, :short)
            @test occursin("<svg", to_svg(Schematic([Bipole(k, Pt(0, 0), Pt(2, 0), "X")])))
        end
        for k in (:npn, :pnp, :nmos, :pmos)
            @test occursin("<svg", to_svg(Schematic([Transistor(k, "T", Pt(0, 0))])))
        end
        @test_throws ErrorException to_svg(Schematic([Bipole(:Z, Pt(0, 0), Pt(1, 0))]))
    end

    @testset "ASCII: polarity markers" begin
        b = only(bipoles(ascii_schematic("a--D1>--b")))
        @test b.kind == :D && b.a.x < b.b.x        # cathode (b) on the right
        b = only(bipoles(ascii_schematic("a--<D1--b")))
        @test b.a.x > b.b.x                         # cathode on the left
        b = only(bipoles(ascii_schematic(" |\n V1\n |")))
        @test b.kind == :V && b.a.y > b.b.y         # '+' (a) on top by default
        b = only(bipoles(ascii_schematic(" |\n V1v\n |")))
        @test b.a.y < b.b.y                         # '+' at the bottom
        b = only(bipoles(ascii_schematic(" |\n I1\n |")))
        @test b.a.y > b.b.y                         # arrow a→b points down
        b = only(bipoles(ascii_schematic(" |\n D1^\n |")))
        @test b.b.y > b.a.y                         # cathode on top
        @test only(bipoles(ascii_schematic("a--G1--b"))).kind == :cI
        @test only(bipoles(ascii_schematic("a--E1--b"))).kind == :cV
    end

    @testset "ASCII: labels and spacing" begin
        b = only(bipoles(ascii_schematic("a--RD--b")))
        @test b.label == "R_{D}"
        b = only(bipoles(ascii_schematic("a--R1--b"; labels=Dict("R1" => "10k"))))
        @test b.label == "10k"
        b = only(bipoles(ascii_schematic("a--R1--b"; dx=1.0)))
        @test b.b.x - b.a.x == 3.0                 # from cell 3 to cell 6
        s = ascii_schematic("a--R1--b"; scale=30.0, background="none")
        @test s.scale == 30.0 && s.background == "none"
    end

    @testset "ASCII: inverting amplifier" begin
        s = schem"""
                    +--gnd
                    |
                    OA1-------+---vout
                    |         |
          vin--R1---+---R2----+
        """
        @test s isa Schematic
        @test count_of(Opamp, s) == 1
        @test count_of(Bipole, s) == 2
        @test count_of(Port, s) == 2
        @test count_of(Ground, s) == 1
        @test count_of(Dot, s) == 2
        @test occursin("<svg", to_svg(s))
    end

    @testset "ASCII: sources, BJT, supplies" begin
        s = schem"""
            vdd             vdd
             |               |
             I1              RC
             |               |
             +-----+         +--vo
             |     |         |
             D1v   C2  in--|Q1
             |     |         |
            gnd   gnd        G1
                             |
                            vss
        """
        @test count_of(Bipole, s) == 5
        @test count_of(Transistor, s) == 1
        @test count_of(Supply, s) == 3
        @test count_of(Ground, s) == 2
        @test count_of(Port, s) == 2
        @test count_of(Dot, s) == 2
        @test any(x -> x isa Supply && x.label == "V_{SS}" && !x.up, s.items)
    end

    @testset "ASCII: CMOS, mirrored gates, crossing" begin
        s = schem"""
                   vdd           vdd
                    |             |
              +---|P1     +------P2|--+
              |     |     |       |   |
          in--*     *-----)-------*   |
              |     |     |       |   |
              +---|N1     |      N2|--+
                    |     |       |
                   gnd    |      gnd
                          |
              vb---<D1----+---E1----out
        """
        ts = filter(x -> x isa Transistor, s.items)
        @test length(ts) == 4
        @test count(t -> t.xflip, ts) == 2         # P2 and N2 have the gate on the right
        @test all(t -> t.yflip == (t.kind == :pmos), ts)
        @test count_of(Dot, s) == 4                 # the ')' crossing gets no dot
        @test count_of(Port, s) == 3
        @test count_of(Supply, s) == 2
    end

    @testset "ASCII: diagnostics" begin
        @test_logs (:warn,) ascii_schematic("R1")
        @test isempty(ascii_schematic("").items)
        @test startswith(to_svg(Schematic()), "<svg")
    end

    @testset "symbols" begin
        # '+' and '−' are drawn upright: for a vertical source both bars are horizontal
        svg = to_svg(Schematic([Bipole(:V, Pt(0, 1), Pt(0, 0))]))
        @test nfind("h7.0", svg) == 2 && nfind("v7.0", svg) == 1
        svg = to_svg(Schematic([Bipole(:cV, Pt(0, 0), Pt(2, 0))]))
        @test nfind("h6.0", svg) == 2
        @test !occursin("h6.0", to_svg(Schematic([Bipole(:cI, Pt(0, 0), Pt(2, 0))])))
    end

    @testset "SI formatting" begin
        @test si(4700, "Ω") == "4.7 kΩ"
        @test si(2.2e-9, "F") == "2.2 nF"
        @test si(1e-6, "F") == "1 µF"
        @test si(1.25, "V") == "1.25 V"
        @test si(-0.005, "A") == "-5 mA"
        @test si(10) == "10"
        @test si(0, "V") == "0 V"
    end

    @testset "annotations" begin
        art = """
             vdd
              |
              R1
              |
              +--@vx--o1
              |
        in--|N1
              |
             gnd
        """
        s = ascii_schematic(art; elements=[Res("r1", 4700), Fet("N1", "nmos_lv"), Res("R9", 1)],
                            nodes=Dict("vx" => 1.5, "in" => raw"$v_{in}$"))
        r = only(bipoles(s))
        @test r.name == "R1" && r.label == "R_{1}" && r.note == "4.7 kΩ"   # case-insensitive
        t = only(filter(x -> x isa Transistor, s.items))
        @test t.note == "nmos_lv"
        @test occursin(">nmos_lv<", to_svg(s))                 # underscore kept literally
        n = only(filter(x -> x isa NodeLabel, s.items))
        @test n.name == "vx" && n.label == "vx = 1.5 V" && n.side == :above
        @test any(x -> x isa Port && x.name == "in" && x.label == raw"$v_{in}$", s.items)
        @test any(x -> x isa Port && x.name == "o1" && x.label == "o1", s.items)

        s = ascii_schematic(art; elements=[(name="R1", value=4700), (name="N1", model="nmos_lv")],
                            style=:inline)
        @test only(bipoles(s)).label == "R_{1} = 4.7 kΩ"
        @test only(filter(x -> x isa Transistor, s.items)).label == "N_{1}: nmos\\_lv"
        @test occursin("nmos_lv", to_svg(s))

        s = ascii_schematic(art; elements=Dict("R1" => "10k"), style=:value)
        @test only(bipoles(s)).label == "10k" && only(bipoles(s)).note == ""

        # annotate also works on hand-placed primitives, by name
        s = annotate(Schematic([Bipole(:C, Pt(0, 0), Pt(1, 0), "C"; name="C3")]), Dict("C3" => 1e-12))
        @test only(bipoles(s)).note == "1 pF"
        @test_throws ArgumentError annotate(s, (); style=:bogus)
        @test annotate(s).items == s.items
    end

    @testset "ASCII: node tags" begin
        # inline tag: the wire passes through and the name sits above it
        s = ascii_schematic("a--@vx--b")
        @test any(x -> x isa Wire && x.pts == [Pt(1, 0), Pt(3, 0)], s.items)
        @test only(filter(x -> x isa NodeLabel, s.items)).side == :above
        # tag at the end of a wire, and under a wire
        @test only(filter(x -> x isa NodeLabel, ascii_schematic("a---@n_1").items)).name == "n_1"
        nl = only(filter(x -> x isa NodeLabel, ascii_schematic("a-----b\n  @3").items))
        @test nl.name == "3" && nl.side == :below
        @test_logs (:warn,) ascii_schematic("@lonely")
    end

    @testset "CircuiTikZ" begin
        src = raw"""
        \begin{circuitikz}
          % a comment; with a semicolon
          \draw (0,0) node[ground]{} to[V, l=$v_{in}$] (0,2) to[R=$R_1$, *-] (3,2) coordinate (out);
          \draw (out) to[C, l_=$C_1$, a=10<\micro F>] ++(0,-2) -- (0,0);
          \draw (5,2) node[nmos, anchor=D](M1){$M_1$};
          \draw (M1.S) node[ground]{} (M1.G) -- ++(-1,0) node[left]{$v_g$};
          \draw (8,0) node[op amp](OA){} (OA.out) to[short, -o] ++(1,0);
        \end{circuitikz}
        """
        s = tikz_schematic(src)
        bs = bipoles(s)
        v = only(filter(b -> b.kind == :V, bs))
        @test near(v.a, Pt(0, 0)) && near(v.b, Pt(0, 2))          # '+' at the path start, as in CircuiTikZ
        @test v.label == raw"$v_{in}$" && v.side == :left && v.name == "vin"
        r = only(filter(b -> b.kind == :R, bs))
        @test r.name == "R1" && r.label == raw"$R_1$" && r.side == :left
        c = only(filter(b -> b.kind == :C, bs))
        @test c.side == :right && c.note == "10 µF" && near(c.b, Pt(3, 0))
        @test count_of(Dot, s) == 1 && count_of(Ground, s) == 2 && count_of(Port, s) == 1

        m = only(filter(x -> x isa Transistor, s.items))
        @test m.w == 0.98 && m.h == 0.77                 # CircuiTikZ dimensions
        @test near(pin(m, :D), Pt(5, 2))                      # anchor=D lands on the path point
        @test any(x -> x isa Ground && near(x.at, pin(m, :S)), s.items)
        @test any(x -> x isa Wire && near(x.pts[end], pin(m, :G) + Pt(-1, 0)), s.items)
        @test any(x -> x isa NodeLabel && x.label == raw"$v_g$" && x.side == :left, s.items)

        o = only(filter(x -> x isa Opamp, s.items))
        @test o.inv_up && near(pin(o, :inn), Pt(8 - 1.19, 0.49)) && near(pin(o, :out), Pt(9.19, 0))
        @test occursin("<svg", to_svg(s))

        # relative coordinates: + keeps the reference point, ++ moves it
        w = [x.pts for x in tikz_schematic(raw"\draw (0,0) -- +(1,0) -- +(0,1) -- ++(2,2) -- +(1,0);").items]
        @test [p[end] for p in w] == [Pt(1, 0), Pt(0, 1), Pt(2, 2), Pt(3, 2)]
        # perpendicular coordinates and -| / |- paths
        w = [x.pts for x in tikz_schematic(raw"\coordinate (A) at (1,3); \draw (0,0) -- (A |- 0,0) -- (A); \draw (4,1) -| (A);").items]
        @test w[1][end] == Pt(1, 0) && w[3] == [Pt(4, 1), Pt(1, 1), Pt(1, 3)]
        # invert flips the symbol; the label stays on the same side of the path
        d = only(bipoles(tikz_schematic(raw"\draw (0,0) to[D, invert, l=$D$] (0,2);")))
        @test d.a == Pt(0, 2) && d.b == Pt(0, 0) && d.side == :right
        # environment scale applies to coordinates; sinusoidal sources
        s2 = tikz_schematic(raw"\begin{circuitikz}[scale=2] \draw (0,0) to[sV] (1,0); \node[ground] at (1,0) {}; \end{circuitikz}")
        @test only(bipoles(s2)).kind == :sV && only(filter(x -> x isa Ground, s2.items)).at == Pt(2, 0)
        # p-type devices: source/emitter on top; op amp + up when flipped
        p = only(tikz_schematic(raw"\draw (0,0) node[pmos](P){};").items)
        @test near(pin(p, :S), Pt(0, 0.77)) && near(pin(p, :D), Pt(0, -0.77))
        @test !only(tikz_schematic(raw"\draw (0,0) node[op amp, noinv input up](O){};").items).inv_up
        # annotations by name, and the string macro
        s3 = tikz_schematic(raw"\draw (0,0) to[R=$R_1$] (2,0);"; elements=Dict("R1" => 1e3))
        @test only(bipoles(s3)).note == "1 kΩ"
        @test tikz"\draw (0,0) to[R] (2,0);" isa Schematic
        # unsupported input warns instead of drawing something wrong
        @test_logs (:warn, r"circle") tikz_schematic(raw"\draw (0,0) circle (1);")
        @test_logs (:warn, r"unknown element") match_mode=:any tikz_schematic(raw"\draw (0,0) to[spark] (2,0);")
        @test_logs (:warn, r"calc") tikz_schematic(raw"\draw ($(0,0)!0.5!(1,0)$) -- (1,1);")
        @test_logs (:warn, r"rotate") tikz_schematic(raw"\draw (0,0) node[nmos, rotate=90]{};")
    end

    @testset "TeX labels" begin
        @test first(SchematicSVG.texlabel(raw"$\mu v_1$")) == "μv<tspan dy=\"4\" font-size=\"10.5\">1</tspan>"
        @test first(SchematicSVG.texlabel(raw"$\Delta V_{\text{out}}$")) == "ΔV<tspan dy=\"4\" font-size=\"10.5\">out</tspan>"
        @test SchematicSVG.siunitx(raw"4.7<\kilo\ohm>") == "4.7 kΩ"
    end

    @testset "netlist" begin
        cmos = """
                     vdd
                      |
                +---|P1
                |     |
          in----*     +--@out--+
                |     |        |
                +---|N1        CL
                |     |        |
                V1   gnd      gnd
                |
               gnd
        """
        n = schematic_netlist(ascii_schematic(cmos); elements=Dict("V1" => 0, "CL" => 1e-12),
                              supplies=Dict("vdd" => 5))
        dev(nm) = only(filter(d -> d.name == nm, n.devices))
        @test dev("P1").kind == :pmos && dev("P1").nodes == ["out", "in", "vdd"]   # D, G, S
        @test dev("N1").kind == :nmos && dev("N1").nodes == ["out", "in", "0"]
        @test dev("CL").nodes == ["out", "0"] && dev("V1").nodes == ["in", "0"]
        @test n.supplies == ["vdd" => 5]
        txt = sprint(print, n)
        @test occursin("VDD vdd 0 DC 5\n", txt)
        @test occursin("MP1 out in vdd vdd ald1105p\n", txt)                       # body = source
        @test occursin("MN1 out in 0 0 ald1105n\n", txt)
        @test occursin("CL out 0 1.0e-12\n", txt) && occursin("V1 in 0 DC 0\n", txt)
        sp = spice_netlist(ascii_schematic(cmos); title="inv", include="lib.sp",
                           elements=Dict("V1" => 0, "CL" => 1e-12), supplies=Dict("vdd" => 5))
        @test startswith(sp, "* inv\n.include lib.sp\n") && endswith(sp, ".end\n")

        # crossings don't connect; a wire carrying two names warns
        cross = """
               vdd
                |
                R1
                |
          a-----)-----b
                |
                R2
                |
               gnd
        """
        n = @test_logs (:warn, r"two names") match_mode=:any schematic_netlist(ascii_schematic(cross);
                        elements=Dict("R1" => 1e3, "R2" => 1e3), supplies=Dict("vdd" => 2))
        @test [d.nodes for d in n.devices] == [["vdd", "n1"], ["n1", "0"]]

        # CircuiTikZ: values read from the drawing, two V_CC symbols are one node
        amp = raw"""
        \begin{circuitikz}
          \draw (0,0) node[ground]{} to[V, l=$v_{in}$] (0,2) to[C=$C_1$, a=10<\micro F>] (2,2) coordinate(B)
                to[R=$R_{B1}$, a=47<\kilo\ohm>, *-] (2,5) node[vcc]{$V_{CC}$};
          \draw (B) to[R=$R_{B2}$, a=10<\kilo\ohm>] (2,0) node[ground]{};
          \draw (B) -- (3.5,2) node[npn, anchor=B](Q1){$Q_1$};
          \draw (Q1.C) to[R=$R_C$, a=4.7k] ++(0,2.23) node[vcc]{$V_{CC}$};
          \draw (Q1.E) to[R=$R_E$, a=1k] ++(0,-1.23) node[ground]{};
          \draw (Q1.C) to[short, *-o] ++(1.5,0) node[right]{$v_o$};
        \end{circuitikz}"""
        n = schematic_netlist(tikz_schematic(amp); elements=Dict("vin" => 0), supplies=Dict("vcc" => 12))
        @test dev("C1").value == 1e-5 && dev("RB1").value == 47e3 && dev("RC").value == 4700
        @test dev("Q1").kind == :npn && dev("Q1").nodes == ["vo", "n2", "n3"]        # C, B, E
        @test dev("RB1").nodes == ["n2", "vcc"] && dev("RC").nodes == ["vo", "vcc"]
        @test dev("vin").nodes == ["0", "n1"]                    # '+' at the path start
        @test n.supplies == ["vcc" => 12]
        @test occursin("Q1 vo n2 n3 Q2N3904\n", sprint(print, n))

        # dependent sources need (gain, control); polarity follows the drawing
        dep = """
          +---V1---+---R1---+--@x
          |                 |
         gnd                R2
                            |
                           gnd
                                 +---E1---+--@y
                                 |        |
                                gnd       R3
                                          |
                                         gnd
        """
        vals = Dict("V1" => 2, "R1" => 1e3, "R2" => 1e3, "R3" => 1e3)
        n = schematic_netlist(ascii_schematic(dep); elements=merge(vals, Dict("E1" => (10, ("x", "0")))))
        @test occursin("E1 0 y x 0 10\n", sprint(print, n))
        @test occursin("H1 0 y Vsense 5\n", sprint(print, schematic_netlist(
            ascii_schematic(replace(dep, "E1" => "H1")); elements=merge(vals, Dict("H1" => (5, "Vsense"))))))
        @test_throws ArgumentError schematic_netlist(ascii_schematic(dep); elements=merge(vals, Dict("E1" => 10)))

        # values: elements given at annotation time are kept; missing ones become {name}
        rc = """
          in--R1--+--out
                  |
                  C1
                  |
                 gnd
        """
        s = ascii_schematic(rc; elements=[Res("R1", 4700)])
        n = @test_logs (:warn, r"no value for C1") match_mode=:any schematic_netlist(s)
        @test only(filter(d -> d.name == "R1", n.devices)).value isa Res
        @test occursin("R1 in out 4700\n", sprint(print, n)) && occursin("C1 out 0 {C1}\n", sprint(print, n))
        @test only(filter(d -> d.name == "C1", schematic_netlist(s; elements=Dict("C1" => 1e-9)).devices)).value == 1e-9

        # a dangling pin warns
        @test_logs (:warn, r"not connected") match_mode=:any schematic_netlist(
            ascii_schematic("  a--R1--b\n\n  R2\n  |\n gnd"); elements=Dict("R1" => 1, "R2" => 1))

        @test parse_value("4.7 kΩ") == 4700 && parse_value("10µF") == 1e-5 && parse_value("2.2n") == 2.2e-9
        @test parse_value("1e3") == 1000 && parse_value("5 V") == 5 && parse_value("1 MΩ") == 1e6
        @test parse_value("1meg") == 1e6 && parse_value("-3 mA") == -3e-3 && parse_value("R1") === nothing

        @test_throws ArgumentError to_microelectronics(ascii_schematic(rc))   # extension not loaded
    end

    @testset "DC paths to ground" begin
        # capacitor-coupled input and output: both nodes float at DC
        amp = """
                 vdd               vdd
                  |                 |
                  RB1               RC
                  |                 |
                  |                 +---C2---vo
                  |                 |
           in--C1-+--@vb-----------|Q1
                  |                 |
                  RB2               RE
                  |                 |
                 gnd               gnd
        """
        vals = Dict("RB1" => 47e3, "RB2" => 10e3, "RC" => 4.7e3, "RE" => 1e3,
                    "C1" => 10e-6, "C2" => 2.2e-6, "Q1" => "Q2N3904")
        @test_logs((:warn, r"node vo has no DC path to ground.*load resistor between vo and ground"),
                   (:warn, r"node in has no DC path to ground.*load resistor between in and ground"),
                   schematic_netlist(ascii_schematic(amp); elements=vals, supplies=Dict("vdd" => 12)))
        # adding the load resistors silences it
        fixed = """
                 vdd               vdd
                  |                 |
                  RB1               RC
                  |                 |
                  |                 +---C2---+---vo
                  |                 |        |
          in-+-C1-+--@vb-----------|Q1       RL
             |    |                 |        |
             RI   RB2               RE      gnd
             |    |                 |
            gnd  gnd               gnd
        """
        @test_logs schematic_netlist(ascii_schematic(fixed); elements=merge(vals, Dict("RL" => 1e4, "RI" => 1e6)),
                                     supplies=Dict("vdd" => 12))
        # a MOSFET gate reached only through a capacitor needs a bias resistor
        gate = """
                vdd
                 |
                 RD
                 |
          +--C1-|N1
          |      |
          VS    gnd
          |
         gnd
        """
        @test_logs (:warn, r"no DC path.*bias resistor between n\d+ and ground") schematic_netlist(
            ascii_schematic(gate); elements=Dict("RD" => 1e4, "C1" => 1e-6, "VS" => 0), supplies=Dict("vdd" => 5))
        # op-amp outputs are driven; inputs are not
        oa = """
                    +--gnd
                    |
                    OA1-------+---vout
                    |         |
          vin--C1---+---R2----+
        """
        @test_logs (:warn, r"node vin has no DC path.*load resistor between vin") schematic_netlist(
            ascii_schematic(oa); elements=Dict("C1" => 1e-6, "R2" => 1e4))
        g, hz = SchematicSVG.dc_floating_groups(
            [NetDevice("R1", :R, ["a", "b"], 1), NetDevice("C1", :C, ["b", "0"], 1)], String[])
        @test g == [["a", "b"]]
        @test_logs (:warn, r"no ground symbol") schematic_netlist(ascii_schematic("  a--R1--b"); elements=Dict("R1" => 1))
    end

    @testset "subcircuits" begin
        cs = """
                                 vdd
                                  |
                                  RD
                                  |
                                  +-@d-CC2----+--out
                                  |           |
          in----CC1--@g----+-----|N1          RL
                           |      |           |
                           RG     +-@s-+     gnd
                           |      |    |
                          gnd     I1   CB
                                  |    |
                                 vss  gnd
        """
        vals = Dict("RD" => 20e3, "RG" => 1e6, "RL" => 1e5, "CC1" => 1e-5, "CC2" => 1e-5,
                    "CB" => 1e-4, "I1" => 1e-4, "N1" => (model="ald1105n", W=20e-6, L=10e-6))
        # terminals and supplies are external: no DC-path or supply warnings
        sub = @test_logs spice_subcircuit(ascii_schematic(cs; elements=vals); name="cs_nmos",
                                         terminals=["in", "out"], rename=Dict("vdd" => "vdd!", "vss" => "vss!"))
        @test startswith(sub, ".subckt cs_nmos in out\n") && endswith(sub, ".ends cs_nmos\n")
        @test occursin("RD vdd! d 20000\n", sub) && occursin("I1 s vss! DC 0.0001\n", sub)
        @test occursin("MN1 d g s s ald1105n W=2.0e-5 L=1.0e-5\n", sub)
        @test occursin("CC1 in g 1.0e-5\n", sub) && occursin("CB s 0 0.0001\n", sub)
        @test occursin(" params: Rx=5", spice_subcircuit(ascii_schematic(cs; elements=vals);
                       name="x", terminals=["in", "out"], params=["Rx" => 5]))
        @test_throws ArgumentError spice_subcircuit(ascii_schematic(cs; elements=vals); name="x", terminals=["in", "vo"])
        # rename and external on a plain netlist
        n = schematic_netlist(ascii_schematic(cs; elements=vals); rename=Dict("vdd" => "vdd!"),
                              external=["in", "vdd", "vss"])
        @test "vdd!" in n.nets && isempty(n.supplies)
        @test_throws ArgumentError to_subcircuit(ascii_schematic(cs); name="x", terminals=["in"])   # extension not loaded
    end

    @testset "quantities in SPICE text" begin
        rc = """
          in--R1--+--out
                  |
                  C1
                  |
                 gnd
        """
        s = ascii_schematic(rc; elements=Dict("R1" => 4.7u"kΩ", "C1" => 10u"μF"))
        @test only(filter(b -> b isa Bipole && b.name == "R1", s.items)).note == "4.7 kΩ"   # drawing keeps units
        txt = spice_netlist(s; external=["in"])
        @test occursin("R1 in out 4700\n", txt) && occursin("C1 out 0 1.0e-5\n", txt)
        @test !occursin("Ω", txt) && !occursin("μ", txt)
        # supplies, MOSFET sizes, sine parameters, gains and subcircuit parameters too
        inv = """
                 vdd
                  |
            +---|P1
            |     |
      in----*     +--out
            |     |
            +---|N1
                  |
                 gnd
        """
        txt = spice_netlist(ascii_schematic(inv); external=["in", "out"], supplies=Dict("vdd" => 5u"V"),
                            elements=Dict("N1" => (model="ald1105n", W=20u"μm", L=10u"μm")))
        @test occursin("VDD vdd 0 DC 5\n", txt) && occursin("MN1 out in 0 0 ald1105n W=2.0e-5 L=1.0e-5\n", txt)
        g = SchematicSVG.spiceline(NetDevice("G1", :G, ["a", "0"], (2u"mS", ("x", "0"))))
        @test g == "G1 a 0 x 0 0.002"
        s1 = SchematicSVG.spiceline(NetDevice("V1", :sV, ["a", "0"], (amplitude=10u"mV", frequency=1u"kHz")))
        @test s1 == "V1 a 0 SIN(0 0.01 1000)"
        @test SchematicSVG.paramtext("Rx" => 4.7u"kΩ") == "Rx=4700"
    end
end

# The Microelectronics.jl extension, when that package is available.
if Base.find_package("Microelectronics") !== nothing
    include("microelectronics.jl")
end
