module _adEq2_memcmp;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { "
        ~ "enum size = " ~ Size ~ ";"
        ~ Struct ~ "[size] a = new  "~ Struct ~ "[size];"
        ~ Struct ~ "[size] b = new  "~ Struct ~ "[size];"
        ~ q{
            // Before the change: lowered to `__adEq2`
            // After the change: lowered to `memcmp`
            assert(a == b);
         } ~ " }";
}
