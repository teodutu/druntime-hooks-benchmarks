module __equals_memcmp;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { "
        ~ "enum size = " ~ Size ~ ";"
        ~ Struct ~ "[] a = new  "~ Struct ~ "[size];"
        ~ Struct ~ "[] b = new  "~ Struct ~ "[size];"
        ~ q{
            // Before the change: lowered to `__equals`
            // After the change: lowered to `memcmp`
            assert(a == b);
         } ~ " }";
}
