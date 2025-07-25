module _d_arrayliteralTX;

template GenArray(size_t Size, string Initializer)
{
    enum GenArray = (){
        string arr = "[";
        static foreach (i; 0 .. Size)
        {
            arr ~= Initializer;
            if (i < Size - 1)
                arr ~= ",";
        }
        return arr ~ "]";
    }();
}

template GenTest(string Struct, string Size, string arr)
{
    const char[] GenTest = "void test" ~ Struct ~ '_' ~ Size ~ "Elems() { "
        ~ "import _d_arrayliteralTX : GenArray;"
        ~ "auto arr = mixin(GenArray!(" ~ Size ~ ",\"" ~ arr ~ "\")); "
        ~ " }";
}
