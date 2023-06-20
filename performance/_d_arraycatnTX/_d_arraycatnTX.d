module _d_arraycatnTX;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { " ~ q{
        } ~ Struct ~ "[] a;" ~ q{
        } ~ Struct ~ "[] b = a ~ a ~ " ~ arr ~ ";}";
}
