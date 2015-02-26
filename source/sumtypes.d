module themain;

import std.stdio;
import std.string;
import std.conv;
import std.traits;
import std.typetuple;


struct SumType(Ts...) {
    static assert (NoDuplicates!Ts.length == Ts.length, "Duplicate types found");

    mixin(() {
        auto s = "enum Cases {";
        foreach(i, _; Ts) {
            s ~= "c" ~ text(i) ~ " = " ~ text(i) ~ ", ";
        }
        return s ~= "unset}\n";
    }());

    Cases which = Cases.unset;
    union {
        Ts cases;
    }

    this(U)(auto ref U val) {
        opAssign(val);
    }
    auto ref opAssign(U)(auto ref U val) {
        enum idx = staticIndexOf!(U, Ts);
        static assert (idx >= 0, U.stringof ~ " does not belong to " ~ Ts.stringof);
        cases[idx] = val;
        which = cast(Cases)idx;
        return this;
    }

    auto caseOf(Fs...)(Fs funcs) {
        static assert (Fs.length == Ts.length);
        final switch (which) {
            foreach(i, f; funcs) {
                alias ptt = ParameterTypeTuple!f;
                static assert (ptt.length == 1);
                enum idx = staticIndexOf!(ptt[0], Ts);
                static assert (idx >= 0, ptt[0].stringof ~ " does not belong to " ~ Ts.stringof);

                case cast(Cases)idx:
                    return funcs[i](cases[idx]);
            }

            case Cases.unset:
                assert (false, "not set");
        }
    }

    string toString() {
        final switch (which) {
            foreach(i, _; Ts) {
                case cast(Cases)i:
                    static if (is(typeof(cases[i].toString) == string)) {
                        return cases[i].toString();
                    }
                    else static if (is(typeof(text(cases[i])))) {
                        return text(cases[i]);
                    }
                    else {
                        return typeof(cases[i]).stringof;
                    }
            }
            case Cases.unset:
                return "<unset>";
        }
    }
}

void patternMatching() {
    SumType!(int, string, double) s;
    s = "hello";

    auto r = s.caseOf(
        (int x) {
            return 100;
        },
        (string x) {
            return 200;
        },
        (double x) {
            return 300;
        }
    );
    writeln(s);
    writeln(r);
}


template DataTree(T) {
    class Empty {override string toString() {return "E";}}
    static Tree empty = Empty.init;

    class Node {
        T val;
        Tree lhs;
        Tree rhs;

        this(T val, Tree lhs, Tree rhs) {this.val = val; this.lhs = lhs; this.rhs = rhs;}
        override string toString() {return format("Node(%s, %s, %s)", val, lhs, rhs);}
    }

    auto node(T val, Tree lhs, Tree rhs) {
        return Tree(new Node(val, lhs, rhs));
    }

    alias Tree = SumType!(Empty, Node);
}

U fold(T, U)(T t, U function(U, U) f, U initVal = U.init) {
    static if (is(T == SumType!(E, N).Tree, E, N)) {
        return t.caseOf(
            (N n) {
                auto r = fold(n.rhs, f, initVal);
                auto l = fold(n.lhs, f, initVal);
                return f(f(n.val, r), l);
            },
            (E e) {
                return initVal;
            }
        );
    }
    else {
        static assert (false, T.stringof ~ " is not a tree");
    }
}

void treeExample() {
    alias Tree1 = DataTree!int;
    auto t1 = Tree1.node(10, Tree1.node(5, Tree1.empty, Tree1.empty), Tree1.node(7, Tree1.empty, Tree1.empty));
    writeln("t1=", t1);

    alias Tree2 = DataTree!string;
    auto t2 = Tree2.node("foo", Tree2.node("bar", Tree2.empty, Tree2.empty), Tree2.node("spam", Tree2.empty, Tree2.empty));
    writeln("t2=", t2);

    writeln("sum=", fold(t1, (int a, int b) => (a+b)));
    writeln("cat=", fold(t2, (string a, string b) => (a ~ b)));
}


template CTOR(string NAME, ARGS...) {
    static if (ARGS.length == 0) {
        final class _CTOR(string NAME) {override string toString() const {return NAME;}}
        __gshared static CTOR = new _CTOR!NAME();
    }
    else {
        final class _CTOR(string NAME) {
            enum name = NAME;
            alias argTypes = ARGS;

            ARGS _args;

            this(ARGS a) {
                _args = a;
            }

            override string toString() const {
                auto s = NAME ~ "(";
                foreach(i, ref a; _args) {
                    static if (i == ARGS.length - 1) {
                        s ~= text(a);
                    }
                    else {
                        s ~= text(a) ~ ", ";
                    }
                }
                return s ~ ")";
            }
        }
        _CTOR!NAME CTOR(ARGS args) {
            return new _CTOR!NAME(args);
        }
    }
}

enum isType(T...) = is(isBuiltinType!(T[0])) || is(T[0] == class) || is(T[0] == struct) || is(T[0] == union) || is(T[0] == enum);

template Data(ctors...) {
    template makeTypes(int i) {
        static if (i == ctors.length) {
            alias makeTypes = TypeTuple!();
        }
        else static if (isType!(ctors[i])) {
            alias makeTypes = TypeTuple!(ctors[i], makeTypes!(i+1));
        }
        else static if (isCallable!(ctors[i])) {
            alias makeTypes = TypeTuple!(ReturnType!(ctors[i]), makeTypes!(i+1));
        }
        else {
            alias makeTypes = TypeTuple!(typeof(ctors[i]), makeTypes!(i+1));
        }
    }

    alias Data = SumType!(makeTypes!0);
}

alias foo = CTOR!"foo";
alias bar = CTOR!("bar", int);

alias spam = Data!(foo, bar);



//alias E2 = CTOR!"E2";
//alias N2 = CTOR!("N2", T2, T2);
//alias T2 = Data!(E2, N2);

void main() {
    patternMatching();
    treeExample();

    spam s = foo;
    writeln(s);
    s = bar(8);
    writeln(s);

}



