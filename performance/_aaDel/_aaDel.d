module _aaDel;

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { "
        ~ "import aa_utils : GenAA;"
        ~ "enum size = " ~ Size ~ ";"
        ~ "auto aa = mixin(GenAA!(" ~ Size ~ "));"
        ~ q{
            foreach (i; 0 .. size)
                aa.remove(i);
        }
        ~ " }";
}
