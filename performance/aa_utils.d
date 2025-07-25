module aa_utils;

template GenAA(size_t Size, string ValueInit = "0")
{
    import std.conv;
    enum GenAA = (){
        string arr = "[";
        static foreach (i; 0 .. Size)
        {
            arr ~= i.to!string ~ ":" ~ ValueInit;
            if (i < Size - 1)
                arr ~= ",";
        }
        return arr ~ "]";
    }();
}
