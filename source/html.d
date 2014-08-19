module weka.web.html;

import std.stdio;
import std.conv;
import std.typetuple;
import std.string;


struct KV {
    string k;
    string v;

    this(T)(string k, T v) {
        this.k = k;
        this.v = to!string(v);
    }
}

struct AttrSetter {
    static AttrSetter instance;

    template opDispatch(string name) {
        @property auto opDispatch(T)(T v) {
            static if(name.length > 1 && name[$-1] == '_') {
                return KV(name[0 .. $-1], v);
            }
            else {
                return KV(name, v);
            }
        }
    }
}

interface HtmlElement {
    abstract string render();
}

class Text: HtmlElement {
    string contents;
    this(string contents) {
        this.contents = contents;
    }
    override string render() {
        return contents;
    }
}

class Comment: HtmlElement {
    string contents;
    this(string contents) {
        this.contents = contents;
    }
    override string render() {
        return "<!-- " ~ contents ~ " -->";
    }
}

class Tag: HtmlElement {
    string tag;
    string[string] attrs;
    HtmlElement[] children;

    this(string tag) {
        this.tag = tag;
    }

    auto reset() {
        children.length = 0;
        return this;
    }

    override string render() {
        string s = "<" ~ tag ~ " ";
        foreach(k, v; attrs) {
            s ~= k ~ "=\"" ~ v ~ "\" ";
        }
        s ~= ">\n";
        foreach(e; children) {
            s ~= e.render();
        }
        s ~= "</" ~ tag ~ ">\n";
        return s;
    }

    @property auto _() {
        return this;
    }
    auto opIndex(T...)(T kvs) {
        foreach(kv; kvs) {
            attrs[kv.k] = kv.v;
        }
        return this;
    }
    auto opDollar(int dim)() {
        return AttrSetter.instance;
    }

    auto _append(string tag) {
        auto e = new Tag(tag);
        children ~= e;
        return e;
    }
    auto _append(string tag, string content) {
        auto e = new Tag(tag);
        e.text(content);
        children ~= e;
        return e;
    }
    auto text(T)(T content) {
        auto e = new Text(to!string(content));
        children ~= e;
        return this;
    }
    alias opCall = text;
    auto comment(string comment) {
        auto e = new Comment(comment);
        children ~= e;
        return this;
    }

    protected static string _makeSubelems(E...)() {
        string s = "";
        foreach(name; E) {
            s ~= "auto " ~ name ~ "(T...)(auto ref T args) {\n";
            static if (name[$-1] == '_') {
                s ~= "    return _append(\"" ~ name[0 .. $-1] ~ "\", args);";
            }
            else {
                s ~= "    return _append(\"" ~ name ~ "\", args);";
            }
            s ~= "}\n";
        }
        return s;
    }

    mixin(_makeSubelems!("head", "title", "meta", "style", "link", "script",
            "body_", "div", "span", "h1", "h2", "h3", "h4", "h5", "h6", "p", "table", "tr", "td",
            "a", "li", "ul", "ol", "img", "br", "em", "strong", "input", "pre", "label", "iframe", ));
}

class Html: Tag {
    this() {
        super("html");
    }
    override string render() {
        return "<!DOCTYPE html>\n" ~ super.render();
    }
}

struct MyPage {
    Html doc;
    Tag header;
    Tag content;
    Tag footer;

    this(string titleText) {
        doc = new Html();
        doc[$.lang = "en"];
        with (doc) {
            with (head) {
                title(titleText);
            }
            with (body_) {
                header = div[$.class_ = "header"];
                content = div[$.class_ = "content"];
                footer = div[$.class_ = "footer"];
                with (footer) {
                    text("(C) 2014");
                }
            }
        }
    }

    auto render() {
        return doc.render();
    }
}


unittest {
    import std.stdio;

    auto mp = MyPage("hello");

    with(mp.header) {
        h1("apple pie");
    }
    with(mp.footer.reset) {
        text("(C) 2015");
    }

    writeln(mp.render);
}


