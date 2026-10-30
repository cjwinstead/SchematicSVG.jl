# Tests for the Microelectronics.jl extension. Run automatically by runtests.jl when
# Microelectronics is installed; on its own: `julia --project test/microelectronics.jl`
# from an environment that has both packages.
using SchematicSVG, Microelectronics, Test

@testset "Microelectronics extension" begin
    flat(x) = strip(replace(string(x), r"\s+" => " "))
    q(f) = redirect_stdout(f, devnull)
    volt(n) = only(Microelectronics.NgHerb.getrealvec(lowercase(n)))

    amp = """
                  vdd               vdd
                   |                 |
                   RB1               RC
                   |                 |
                   |                 +---C2---+--@vo
                   |                 |        |
       +--RS--C1---+--@vb-----------|Q1       RL
       |           |                 |        |
       VS          RB2               RE      gnd
       |           |                 |
      gnd         gnd               gnd
    """
    # Objects with placeholder nodes: the drawing supplies the topology.
    parts = [Resistor("RB1", 0, 0, 47u"kΩ"), Resistor("RB2", 0, 0, 10u"kΩ"),
             Resistor("RC", 0, 0, 4.7u"kΩ"), Resistor("RE", 0, 0, 1u"kΩ"),
             Resistor("RL", 0, 0, 10u"kΩ"), Resistor("RS", 0, 0, 50u"Ω"),
             Capacitor("C1", 0, 0, 10u"μF"), Capacitor("C2", 0, 0, 2.2u"μF"),
             Vdc("VS", 0, 0, 0u"V")]
    s = ascii_schematic(amp; elements=parts)
    ckt = to_microelectronics(s; elements=Dict("Q1" => "Q2N3904"), supplies=Dict("vdd" => 12u"V"))
    @test ckt.sources isa Vector{Microelectronics.Element}
    @test ckt.components isa Vector{Microelectronics.Element}
    lines = Set(flat.(vcat(ckt.sources, ckt.components)))
    @test "VDD vdd 0 dc 12" in lines
    @test "RB1 vdd vb 47000" in lines
    @test "RB2 vb 0 10000" in lines
    @test "Q1 n1 vb n4 Q2N3904" in lines
    @test "C2 n1 vo 2.2e-06" in lines

    q(() -> (build_netlist(; ckt...); simulate(:op)))
    @test 1.9 < volt("vb") < 2.2                          # divider loaded by the base
    @test 4 < volt("n1") < 8                              # collector biased mid-supply

    # Built from plain values, including a MOSFET pair and a sinusoidal source
    inv = """
                 vdd
                  |
            +---|P1
            |     |
      in----*     +--@out
            |     |
            +---|N1
            |     |
            V1   gnd
            |
           gnd
    """
    ckt = to_microelectronics(ascii_schematic(inv); elements=Dict("V1" => 5u"V"), supplies=Dict("vdd" => 5u"V"))
    lines = Set(flat.(vcat(ckt.sources, ckt.components)))
    @test "MP1 out in vdd vdd ald1105p" in lines && "MN1 out in 0 0 ald1105n" in lines
    q(() -> (build_netlist(; ckt...); simulate(:op)))
    @test volt("out") < 0.1

    # Dependent sources: objects keep their control and gain
    dep = """
      +---V1---+--@x
      |        |
     gnd       R1
               |
              gnd
                       +---G1---+--@y
                       |        |
                      gnd       R2
                                |
                               gnd
    """
    ckt = to_microelectronics(ascii_schematic(dep);
        elements=[Vdc("V1", 0, 0, 1u"V"), Resistor("R1", 0, 0, 1u"kΩ"), Resistor("R2", 0, 0, 1u"kΩ"),
                  VCCS(name="1", nplus="a", nminus="b", control=["x", "0"], gain=1e-3)])
    @test "G1 0 y x 0 0.001" in Set(flat.(ckt.components))

    # SPICE text formats quantities with Microelectronics' qstr
    rc = """
      in--R1--+--out
              |
              C1
              |
             gnd
    """
    txt = spice_netlist(ascii_schematic(rc; elements=Dict("R1" => 4.7u"kΩ", "C1" => 10u"μF")); external=["in"])
    @test occursin("R1 in out $(qstr(4.7u"kΩ"))\n", txt) && occursin("C1 out 0 $(qstr(10u"μF"))\n", txt)
    @test occursin("C1 out 0 1e-05\n", txt)
end
