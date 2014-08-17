import std.conv;
import std.typetuple;
import std.traits;


enum isPacker(T) = __traits(hasMember, T, "pack") && __traits(hasMember, T, "unpack");

struct Context(T, U) {
    T* _ctx;
    U* _;
    alias _ctx this;
}
auto linkContext(T, U)(ref T t, ref U u) {
    return Context!(T, U)(&t, &u);
}

struct Field(T) {
    static assert (isNumeric!T);
    T val;

    void pack(U)(ref ubyte[] stream, U ctx) {
        stream ~= (cast(ubyte*)&val)[0 .. val.sizeof];
    }
    void unpack(U)(ref ubyte[] stream, U ctx) {
        val = *(cast(T*)stream.ptr);
        stream = stream[val.sizeof .. $];
    }
    void pack(ref ubyte[] stream) {
        pack(stream, null);
    }
    void unpack(ref ubyte[] stream) {
        unpack(stream, null);
    }

    string toString() {
        return text(val);
    }

    void opAssign(T rhs) {
        val = rhs;
    }
    void opOpAssign(string op)(T rhs) {
        mixin("val " ~ op ~ "= rhs;");
    }
}


struct Array(T, U...) if (U.length == 1) {
    enum L = U[0];
    static if (isNumeric!T) {
        alias TT = Field!T;
    }
    else {
        alias TT = T;
    }

    static if (is(typeof(L): size_t)) {
        TT[L] elements;

        void pack(S)(ref ubyte[] stream, S ctx) {
            auto ctx2 = linkContext(this, ctx);
            foreach(ref e; elements) {
                e.pack(stream, ctx2);
            }
        }
        void unpack(S)(ref ubyte[] stream, S ctx) {
            auto ctx2 = linkContext(this, ctx);
            foreach(ref e; elems) {
                e.unpack(stream, ctx2);
            }
        }
    }
    else static if (is(typeof(L) == string)) {
        TT[] elements;

        void pack(S)(ref ubyte[] stream, ref S ctx) {
            auto ctx2 = linkContext(this, ctx);
            foreach(i; 0 .. mixin("ctx." ~ L).val) {
                elements[i].pack(stream, ctx2);
            }
        }
        void unpack(S)(ref ubyte[] stream, ref S ctx) {
            auto ctx2 = linkContext(this, ctx);
            elements.length = mixin("ctx." ~ L).val;
            foreach(ref e; elements) {
                e.unpack(stream, ctx2);
            }
        }
    }
    else {
        static assert (false, L.stringof);
    }

    void pack()(ref ubyte[] stream) {
        pack(stream, null);
    }
    void unpack()(ref ubyte[] stream) {
        unpack(stream, null);
    }

    string toString() {
        auto s = "[";
        foreach(ref e; elements) {
            s ~= text(e) ~ ", ";
        }
        return ((s.length > 2) ? s[0 .. $-2] : s) ~ "]";
    }
}

mixin template Record() {
    void pack(S)(ref ubyte[] stream, S ctx) {
        auto ctx2 = linkContext(this, ctx);
        foreach(ref f; this.tupleof) {
            static if (isPacker!(typeof(f))) {
                f.pack(stream, ctx2);
            }
        }
    }

    void unpack(S)(ref ubyte[] stream, S ctx) {
        auto ctx2 = linkContext(this, ctx);
        foreach(ref f; this.tupleof) {
            static if (isPacker!(typeof(f))) {
                f.unpack(stream, ctx2);
            }
        }
    }

    void pack()(ref ubyte[] stream) {
        pack(stream, null);
    }
    void unpack()(ref ubyte[] stream) {
        unpack(stream, null);
    }

    string toString() {
        auto s = "{";
        enum names = TypeTuple!(__traits(allMembers, typeof(this)));
        foreach(i, ref f; this.tupleof) {
            static if (isPacker!(typeof(f))) {
                s ~= names[i] ~ ": " ~ text(f) ~ ", ";
            }
        }
        return ((s.length > 2) ? s[0 .. $-2] : s) ~ "}";
    }
}

struct Computed(T, alias packFunc, alias unpackFunc=packFunc) {
    T val;

    void pack(S)(ref ubyte[] stream, S ctx) {
        val = packFunc(ctx);
    }
    void unpack(S)(ref ubyte[] stream, S ctx) {
        val = unpackFunc(ctx);
    }

    string toString() {
        return text(val);
    }
}

struct PascalString {
    Field!ubyte length;
    Array!(Field!ubyte, "length") data;

    mixin Record!();
}

struct MyStruct {
    Field!ubyte length;
    YourStruct child;

    mixin Record!();
}

struct YourStruct {
    Field!ubyte extra;
    Array!(Field!ubyte, "_.length") data;

    static int compFunc(S)(S ctx) {
        return ctx.extra.val * 17;
    }

    Computed!(int, compFunc) comp;

    mixin Record!();
}

unittest {
    import std.stdio;

    PascalString ps;
    auto stream = cast(ubyte[])"\x05helloXXXX";
    ps.unpack(stream);
    writeln(ps);

    MyStruct ms;
    stream = cast(ubyte[])"\x05\xffhelloXXXX";
    ms.unpack(stream);
    writeln(ms);

    ms.child.extra = 65;
    ubyte[] stream2;
    ms.pack(stream2);
    writeln(stream2);

}


