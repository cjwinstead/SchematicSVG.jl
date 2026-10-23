using SchematicSVG
using Test

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
end
