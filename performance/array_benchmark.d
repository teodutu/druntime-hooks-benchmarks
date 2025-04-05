module array_benchmark;

import std.stdio : writeln;
import std.datetime.stopwatch : benchmark;
import std.math : sqrt;
import std.algorithm : reduce;

enum hooks = ["_d_arrayctor", "_d_arrayappendT", "_d_arraycatT",
    "_d_arraycatnTX", "_d_arrayassign", "_d_newarrayT", "_d_arraysetcapacity"];

static foreach (hook; hooks)
    mixin("version (" ~ hook ~ ") import " ~ hook ~ " : GenTest;");

template GenStruct(string Size, string Var, string Buf)
{
    const char[] GenStruct = "struct _" ~ Size ~ "B_Struct { " ~ Buf ~ " this(this) { } }\n" ~
        "_" ~ Size ~ "B_Struct[1] " ~ Var ~ "s;\n" ~
        "_" ~ Size ~ "B_Struct[64] " ~ Var ~ "m;\n" ~
        "_" ~ Size ~ "B_Struct[256] " ~ Var ~ "l;\n\n";
}

mixin(GenStruct!("0", "s", ""));
mixin(GenStruct!("64", "m", "char[64] x = 1;"));
mixin(GenStruct!("256", "l", "char[256] x = 1;"));


static immutable sizes = ["1", "64", "256"];
static immutable sizesElems = ["_1Elems", "_64Elems", "_256Elems"];
static immutable structs = ["_0B_Struct", "_64B_Struct", "_256B_Struct"];
static immutable letters = ["s", "m", "l"];

static foreach (i, st; structs)
    static foreach (j, sz; sizes)
        mixin(GenTest!(st, sz, letters[i] ~ letters[j]));


void runTest(void function() func, string funcName, uint runs)
{
    double[] times;
    for (int j = 0; j != 100; ++j)
        times ~= cast(double) benchmark!(func)(runs)[0].total!"msecs";

    auto n = times.length;
    auto avg = reduce!((a, b) => a + b / n)(0.0f, times);
    auto sd = sqrt(reduce!((a, b) => a + (b - avg) * (b - avg) / n)(0.0f, times));

    writeln(funcName, " @ ", runs, " runs:\taverage time = ", avg, "ms; \tstd dev = ", sd);
}

void main()
{
    static foreach (st; structs)
        static foreach (i, sz; sizesElems)
            mixin("runTest(&test" ~ st ~ sz ~ ", \"" ~ st ~ sz ~ "\", 1_000_000U);");
}
