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
    size_t calcSize(U)(U ctx) {
        return T.sizeof;
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

    auto opCast(U)() if (isImplicitlyConvertible!(T, U)){
        return cast(U)val;
    }
    void opAssign(T rhs) {
        val = rhs;
    }
    void opOpAssign(string op)(T rhs) {
        mixin("val " ~ op ~ "= rhs;");
    }
    auto opBinary(string op, U)(U rhs) {
        return mixin("val " ~ op ~ " rhs");
    }
    bool opEquals(U)(auto ref const U rhs) const {
        return val == rhs;
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
        size_t calcSize(S)(S ctx) {
            return elements[0].calcSize(ctx) * L;
        }
    }
    else static if (is(typeof(L) == string)) {
        TT[] elements;

        void pack(S)(ref ubyte[] stream, S ctx) {
            auto ctx2 = linkContext(this, ctx);
            foreach(i; 0 .. mixin("ctx." ~ L).val) {
                elements[i].pack(stream, ctx2);
            }
        }
        void unpack(S)(ref ubyte[] stream, S ctx) {
            auto ctx2 = linkContext(this, ctx);
            elements.length = mixin("ctx." ~ L).val;
            foreach(ref e; elements) {
                e.unpack(stream, ctx2);
            }
        }
        size_t calcSize(S)(S ctx) {
            return elements[0].calcSize(ctx) * mixin("ctx." ~ L).val;
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

    auto ref opIndex(size_t index) {
        return elements[index];
    }
    auto opDollar() {
        return elements.length;
    }
    @property auto length() const @safe nothrow pure {
        return elements.length;
    }

    string toString() {
        auto s = "[";
        foreach(ref e; elements) {
            s ~= text(e) ~ ", ";
        }
        return ((s.length > 2) ? s[0 .. $-2] : s) ~ "]";
    }
}

struct Repeater(T, cond...) if (cond.length == 1) {
    T[] elements;

    static if (is(typeof(cond[0]) == string)) {
        enum COND = cond[0];

        void pack(S)(ref ubyte[] stream, S ctx) {
            auto ctx2 = linkContext(this, ctx);
            import std.stdio; writeln(elements);
            foreach(ref e; elements) {
                e.pack(stream, ctx2);
                if (!(mixin(COND ~ "(e)"))) {
                    break;
                }
            }
        }
        void unpack(S)(ref ubyte[] stream, S ctx) {
            auto ctx2 = linkContext(this, ctx);
            elements.length = 0;
            while (true) {
                auto tmp = T.init;
                tmp.unpack(stream, ctx2);
                if (!(mixin(COND ~ "(tmp)"))) {
                    break;
                }
                elements ~= tmp;
            }
        }

    }
    else {
        static assert (false, cond[0].stringof);
    }

    auto ref opIndex(size_t index) {
        return elements[index];
    }
    auto opDollar() {
        return elements.length;
    }
    @property auto length() const @safe nothrow pure {
        return elements.length;
    }
    void opAssign(U)(U[] rhs) {
        elements.length = rhs.length;
        foreach(i, v; rhs) {
            elements[i] = v;
        }
    }

    string toString() {
        return text(elements);
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
    size_t calcSize(S)(S ctx) {
        size_t size;
        foreach(ref f; this.tupleof) {
            static if (isPacker!(typeof(f))) {
                size += f.calcSize();
            }
        }
        return size;
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
    size_t calcSize(S)(S ctx) {
        return 0;
    }

    string toString() {
        return text(val);
    }
}

import std.stdio;

unittest {
    static struct PascalString {
        Field!ubyte length;
        Array!(Field!ubyte, "length") data;

        mixin Record!();
    }

    PascalString ps;
    auto stream = cast(ubyte[])"\x05helloXXXX".dup;
    ps.unpack(stream);
    writeln(ps);
    // {length: 5, data: [104, 101, 108, 108, 111]}
}

unittest {
    static struct YourStruct {
        Field!ubyte extra;
        Array!(Field!ubyte, "_.length") data;

        static int compFunc(S)(S ctx) {
            return ctx.extra + ctx._.length * 2;
        }

        Computed!(int, compFunc) comp;

        mixin Record!();
    }

    static struct MyStruct {
        Field!ubyte length;
        YourStruct child;

        mixin Record!();
    }

    MyStruct ms;
    auto stream = cast(ubyte[])"\x05\xffhelloXXXX".dup;
    ms.unpack(stream);
    writeln(ms);
    // {length: 5, child: {extra: 255, data: [104, 101, 108, 108, 111], compFunc: 265}}

    ms.child.extra = 65;
    ubyte[] stream2;
    ms.pack(stream2);
    writeln(stream2);
    // [5, 65, 104, 101, 108, 108, 111]
}

unittest {
    static struct CString {
        Repeater!(Field!ubyte, q{(c) {return c != 0;}}) chars;

        mixin Record;
    }

    CString cs;
    auto stream = cast(ubyte[])"hello\x00XXXX".dup;
    cs.unpack(stream);

    writeln(cs);
    // {chars: [104, 101, 108, 108, 111]}

    ubyte[] stream2;
    cs.chars = cast(ubyte[])[1, 2, 3, 4, 0, 5, 6, 7];
    cs.pack(stream2);
    writeln(stream2);
    // [1, 2, 3, 4, 0]
}


