module _d_arrayctor;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ Size ~ "() { " ~ Struct ~ "[" ~ arr ~ ".length] a = " ~ arr ~ "; }";
}
