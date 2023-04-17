module _d_arraycatT;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ Size ~ "() { " ~ q{
        } ~ Struct ~ "[] a;" ~ q{
        } ~ Struct ~ "[] b = a ~ " ~ arr ~ ";}";
}
