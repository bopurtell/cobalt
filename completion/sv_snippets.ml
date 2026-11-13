let make collection prefix description body : Snippet_definition.t =
  { id = "sv." ^ prefix; prefix; scopes = [ "systemverilog" ]
  ; collection; description; body }
;;

let design = make "sv.design"
let verification = make "sv.verification"

(* Register vocabulary reference for future documentation:
   https://docs.amd.com/r/en-US/ug953-vivado-7series-libraries/FDRE
   (and FDSE, FDCE, FDPE in the same guide).
   The portal requires JavaScript; the published vendor behavioral models were
   inspected at https://github.com/Xilinx/XilinxUnisimLibrary/tree/master/verilog/src/unisims
   files FDRE.v, FDSE.v, FDCE.v, FDPE.v (2017.1). Default uninverted controls
   are active high, rising-edge clocked, with reset/set ahead of CE. INIT is 0
   for FDRE/FDCE and 1 for FDSE/FDPE; GSR, inversion, timing and X/Z handling
   also exist in those models. These generic templates intentionally make no
   named primitive equivalence claim: they omit those vendor-specific semantics,
   initialization and any synthesis mapping guarantee. *)

let all =
  [ design "aff" "Clocked always block"
      "always_ff @(${1|posedge,negedge|} ${2:clk_i}) begin\n    $0\nend"
  ; design "acomb" "Combinational always block"
      "always_comb begin\n    $0\nend"
   ; design "mod" "Module declaration with spaced port section"
       {|module
  ${1:${TM_FILENAME_BASE:module_name}}

// Port
(
    $0
);

endmodule|}
   ; design "pint" "Unsigned integer parameter"
       {|parameter int unsigned ${1:PARAM_NAME} = ${2:8},$0|}
   ; design "ilog" "Input logic port"
       {|input  logic ${1:signal_i},$0|}
   ; design "olog" "Output logic port"
       {|output logic ${1:signal_o},$0|}
  ; design "inst" "Module instance"
      "${1:module_name} ${2:instance_name} (\n    .${3:port}($3)$0\n);"
  ; design "genfor" "Generate loop"
      "for (genvar ${1:i} = 0; $1 < ${2:COUNT}; $1++) begin : ${3:gen_block}\n    $0\nend"
  ; design "affr" "Register: synchronous active-high reset, rising clock"
      {|always_ff @(posedge ${1:clk}) begin
    if (${2:rst})
        ${3:q} <= ${4:'0};
    else
        $3 <= ${5:d};
    $0
end|}
  ; design "affrn" "Register: synchronous active-low reset, rising clock"
      {|always_ff @(posedge ${1:clk}) begin
    if (!${2:rst_n})
        ${3:q} <= ${4:'0};
    else
        $3 <= ${5:d};
    $0
end|}
  ; design "affar" "Register: asynchronous active-high reset, rising clock"
      {|always_ff @(posedge ${1:clk} or posedge ${2:rst}) begin
    if ($2)
        ${3:q} <= ${4:'0};
    else
        $3 <= ${5:d};
    $0
end|}
  ; design "affarn" "Register: asynchronous active-low reset, rising clock"
      {|always_ff @(posedge ${1:clk} or negedge ${2:rst_n}) begin
    if (!$2)
        ${3:q} <= ${4:'0};
    else
        $3 <= ${5:d};
    $0
end|}
  ; design "affe" "Register: active-high enable, otherwise hold, rising clock"
      {|always_ff @(posedge ${1:clk}) begin
    if (${2:en})
        ${3:q} <= ${4:d};
    $0
end|}
  ; design "affre" "FDRE vocabulary: generic synchronous active-high reset before enable; no primitive instantiation or mapping guarantee"
      {|always_ff @(posedge ${1:clk}) begin
    if (${2:rst})
        ${3:q} <= ${4:'0};
    else if (${5:en})
        $3 <= ${6:d};
    $0
end|}
  ; design "affare" "Generic RTL: asynchronous active-high reset before enable; otherwise hold"
      {|always_ff @(posedge ${1:clk} or posedge ${2:rst}) begin
    if ($2)
        ${3:q} <= ${4:'0};
    else if (${5:en})
        $3 <= ${6:d};
    $0
end|}
  ; design "affarne" "Register: asynchronous active-low reset before active-high enable"
      {|always_ff @(posedge ${1:clk} or negedge ${2:rst_n}) begin
    if (!$2)
        ${3:q} <= ${4:'0};
    else if (${5:en})
        $3 <= ${6:d};
    $0
end|}
  ; design "affse" "FDSE vocabulary: generic synchronous active-high set to all ones before enable; no primitive instantiation or mapping guarantee"
      {|always_ff @(posedge ${1:clk}) begin
    if (${2:set})
        ${3:q} <= '1;
    else if (${4:en})
        $3 <= ${5:d};
    $0
end|}
  ; design "affce" "FDCE vocabulary: generic asynchronous active-high clear to zero before enable; no primitive instantiation or mapping guarantee"
      {|always_ff @(posedge ${1:clk} or posedge ${2:clr}) begin
    if ($2)
        ${3:q} <= '0;
    else if (${4:en})
        $3 <= ${5:d};
    $0
end|}
  ; design "affpe" "FDPE vocabulary: generic asynchronous active-high preset to all ones before enable; no primitive instantiation or mapping guarantee"
      {|always_ff @(posedge ${1:clk} or posedge ${2:pre}) begin
    if ($2)
        ${3:q} <= '1;
    else if (${4:en})
        $3 <= ${5:d};
    $0
end|}
  ; design "acombd" "Combinational defaults before conditional overrides (avoid latches)"
      {|always_comb begin
    ${1:result} = ${2:'0};
    if (${3:condition}) begin
        $1 = ${4:value};
    end
    $0
end|}
   ; design "if" "If statement"
       {|if (${1:condition}) begin
    $0
end|}
   ; design "ifelse" "If/else statement"
       {|if (${1:condition}) begin
    ${2:// true branch}
end else begin
    ${3:// false branch}
end
$0|}
   ; design "else" "Else branch"
       {|else begin
    $0
end|}
   ; design "case" "Case statement with explicit default branch"
       {|case (${1:selector})
    ${2:VALUE}: begin
        ${3:// branch}
    end
    default: begin
        ${4:// default behavior}
    end
endcase
$0|}
   ; design "ucase" "Unique case with explicit default branch"
      {|unique case (${1:selector})
    ${2:VALUE}: begin
        ${3:// branch}
    end
    default: begin
        ${4:// default behavior}
    end
endcase
$0|}
  ; design "pstruct" "Packed struct typedef with editable members"
      {|typedef struct packed {
    ${1:logic valid;}
    ${2:logic [7:0] data;}
\} ${3:payload_t};
$0|}
  ; design "enum" "Enum typedef: explicit binary values, editable base type and states"
      {|typedef enum ${1:logic [1:0]} {
    ${2:IDLE = 2'd0, BUSY = 2'd1}
\} ${3:state_t};
$0|}
  ; design "tvec" "Packed vector typedef"
      {|typedef logic [${1:WIDTH}-1:0] ${2:word_t};
$0|}
  ; design "logicv" "Packed logic vector declaration"
      {|logic [${1:WIDTH}-1:0] ${2:data};
$0|}
  ; design "lparam" "Typed local parameter"
      {|localparam ${1:int unsigned} ${2:COUNT} = ${3:8};
$0|}
   ; design "modp" "Parameterized module with spaced parameter and port sections"
       {|module
  ${1:${TM_FILENAME_BASE:module_name}}

// Params
#(
    parameter int unsigned ${2:DATA_W} = ${3:8}
)

// Port
(
    input  logic ${4:clk_i},
    input  logic [$2 - 1 : 0] ${5:data_i},
    output logic [$2 - 1 : 0] ${6:data_o}
);

    $0

endmodule|}
  ; design "genif" "Conditional generate with named true and false blocks"
      {|if (${1:ENABLE}) begin : ${2:gen_enabled}
    ${3:// enabled implementation}
end else begin : ${4:gen_disabled}
    ${5:// disabled implementation}
end
$0|}
  ; design "fsmreg" "FSM state register: synchronous active-high reset to explicit initial state"
      {|always_ff @(posedge ${1:clk}) begin
    if (${2:rst})
        ${3:state} <= ${4:IDLE};
    else
        $3 <= ${5:state_next};
    $0
end|}
  ; design "fsmnext" "FSM next-state logic: hold by default, illegal-state recovery to IDLE"
      {|always_comb begin
    ${1:state_next} = ${2:state}; // Hold unless a transition is taken.
    unique case ($2)
        ${3:IDLE}: begin
            if (${4:start}) $1 = ${5:BUSY};
        end
        $5: begin
            if (${6:done}) $1 = $3;
        end
        default: $1 = $3; // Explicit recovery policy; review for your design.
    endcase
    $0
end|}
  ; design "fsm" "FSM scaffold: explicit binary encoding, sync high reset, hold/recover policy"
      {|// Explicit binary encoding; review width/values when adding states.
typedef enum logic [1:0] {
    ${1:IDLE} = 2'd0,
    ${2:BUSY} = 2'd1
\} ${3:state_t};
$3 ${4:state}, ${5:state_next};

always_ff @(posedge ${6:clk}) begin
    if (${7:rst}) $4 <= $1;
    else $4 <= $5;
end

always_comb begin
    $5 = $4; // Hold unless a transition is taken.
    unique case ($4)
        $1: if (${8:start}) $5 = $2;
        $2: if (${9:done}) $5 = $1;
        default: $5 = $1; // Illegal-state recovery policy; review explicitly.
    endcase
    $0
end|}
  ; verification "tbclk" "Simulation clock: explicit time literal half-period; enclosing precision must resolve it"
      {|logic ${1:t_clk} = 1'b0;
always #(${2:5ns}) $1 = ~$1;
$0|}
  ; verification "tbrst" "Simulation active-low reset: hold for rising edges, release on falling edge"
      {|initial begin
    ${1:t_rst} = 1'b0;
    repeat (${2:4}) @(posedge ${3:t_clk});
    @(negedge $3);
    $1 = 1'b1;
    $0
end|}
  ; verification "tbtimeout" "Simulation timeout: explicit time literal, fatal exit; enclosing precision applies"
      {|initial begin
    #(${1:100us});
    \$fatal(1, "${2:Simulation timeout}");
    $0
end|}
  ; verification "tbdump" "Simulation VCD dump: simulator-dependent dumpfile/dumpvars support"
      {|initial begin
    \$dumpfile("${1:${TM_FILENAME_BASE:waves}}.vcd");
    \$dumpvars(0, ${2:${TM_FILENAME_BASE:tb}});
    $0
end|}
  ; verification "tb" "Simulation testbench: DUT parameters, t_ signals, active-low reset, falling-edge stimulus, timeout"
      {|module ${1:${TM_FILENAME_BASE:tb}};
    timeunit 1ns;
    timeprecision 1ps;

    // Params
    localparam int unsigned ${2:DATA_W} = ${3:8};

    logic ${4:t_clk} = 1'b0;
    logic ${5:t_rst} = 1'b0;
    always #(${6:5ns}) $4 = ~$4;

    ${7:dut_module}
    #(
        .$2($2)
    )
    ${8:dut_inst0}
      (
        .${9:clk_i}($4),
        .${10:rst_n_i}($5)
      );

    initial begin
        repeat (${11:4}) @(posedge $4);
        @(negedge $4);
        $5 = 1'b1;
        // Drive stimulus on falling edges; sample checks after DUT updates.
        $0
        repeat (4) @(negedge $4);
        \$display("Test complete");
        \$finish;
    end

    initial begin
        #(${12:100us});
        \$fatal(1, "Simulation timeout");
    end
endmodule|}
  ; verification "sva" "Concurrent assertion: posedge sampled, asynchronous disable iff active-low reset (use 1 for none)"
      {|${1:a_check}: assert property (@(posedge ${2:t_clk}) disable iff (!${3:t_rst})
    ${4:condition})
    else \$error("${5:Assertion failed}");
$0|}
  ; verification "prop" "Named property and assertion: posedge sampling, active-low reset disable iff (use 1 for none)"
      {|property ${1:p_check};
    @(posedge ${2:t_clk}) disable iff (!${3:t_rst})
        ${4:condition};
endproperty
${5:a_check}: assert property ($1);
$0|}
  ; verification "coverp" "Cover property: posedge sampling, active-low reset disable iff (use 1 for none)"
      {|${1:c_event}: cover property (@(posedge ${2:t_clk}) disable iff (!${3:t_rst})
    ${4:condition});
$0|}
  ; verification "svaimp" "SVA implication: |-> same sampled cycle; choice |=> starts next sampled cycle"
      {snippet|${1:a_response}: assert property (@(posedge ${2:t_clk}) disable iff (!${3:t_rst})
    (${4:request}) ${5|\|->,\|=>|} (${6:acknowledge}));
$0|snippet}
  ; verification "svabound" "SVA bounded response: |-> ##[MIN:MAX] cycles from request sample, inclusive bounds"
      {|${1:a_bounded_response}: assert property (@(posedge ${2:t_clk}) disable iff (!${3:t_rst})
    (${4:request}) |-> ##[${5:1}:${6:4}] (${7:acknowledge}));
$0|}
  ]
;;
