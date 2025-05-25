module performance._d_arraysetcapacity._d_arraysetcapacity;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { " ~ q{
        } ~ Struct ~ "[] a;" ~ q{
        } ~ "a.reserve(" ~ Size ~ "); }";
}

