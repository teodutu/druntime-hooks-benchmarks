module _aaGetX;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { "
        ~ "import aa_utils : GenAA;"
        ~ "enum size = " ~ Size ~ ";"
        ~ "static aa = mixin(GenAA!(" ~ Size ~ "));"
        ~ q{
            foreach (i; 0 .. size)
                aa.require(i, 0);
        }
        ~ " }";
}
