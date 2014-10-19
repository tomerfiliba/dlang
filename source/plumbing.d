module plumbing;

import std.string;
import std.process;
import std.array: appender;


struct ProcessResult {
    int retcode;
    string stdout;
    string stderr;
}

class BaseCommand {
    auto opIndex(string[] args...) {
        return new BoundCommand(this, args);
    }
    auto opCall(string[] args...) {
        return run(args).stdout;
    }
    auto opBinary(string op: "|")(BaseCommand rhs) {
        return new Pipeline(this, rhs);
    }
    auto opBinary(string op: "&")(BaseCommand rhs) {
        return new ConcurrentCommand(this, rhs);
    }
    auto opBinary(string op)(string filename) if (op == ">" || op == "<" || op == ">=") {
        return new Redirected!op(this, filename);
    }

    abstract ProcessPipes popen(string[] args);

    auto run(string[] args...) {
        return runProc(popen(args));
    }
}

class BoundCommand: BaseCommand {
    BaseCommand underlying;
    string[] args;

    this(BaseCommand underlying, string[] args) {
        this.underlying = underlying;
        this.args = args;
    }
    override ProcessPipes popen(string[] args) {
        return underlying.popen(this.args ~ args);
    }
}

class Pipeline: BaseCommand {
    BaseCommand lhs;
    BaseCommand rhs;

    this(BaseCommand lhs, BaseCommand rhs) {
        this.lhs = lhs;
        this.rhs = rhs;
    }

    override ProcessPipes popen(string[] args) {
        auto lhsProc = lhs.popen(args);
        //auto rhsPid = spawnProcess();
        return lhsProc;
    }
}

class LocalCommand: BaseCommand {
    string executable;

    this(string executable) {
        this.executable = executable;
    }
    override ProcessPipes popen(string[] args) {
        return pipeProcess([executable] ~ args);
    }
}

struct LocalMachine {
    LocalCommand which;

    auto opIndex(string progname) {
        if (which is null) {
            which = new LocalCommand("/usr/bin/which");
        }
        return new LocalCommand(which(progname).chomp);
    }
}

auto runProc(P)(P proc) {
    auto stdout = appender!(ubyte[])();
    auto stderr = appender!(ubyte[])();
    auto outReader = proc.stdout.byChunk(4096);
    auto errReader = proc.stderr.byChunk(4096);

    while (true) {
        if (!outReader.empty) {
            stdout.put(outReader.front);
            outReader.popFront();
        }
        if (!errReader.empty) {
            stderr.put(errReader.front);
            errReader.popFront();
        }
        auto res = tryWait(proc.pid);
        if (res.terminated) {
            break;
        }
    }
    auto rc = wait(proc.pid);
    return ProcessResult(rc, cast(string)stdout.data, cast(string)stderr.data);
}

LocalMachine local;

unittest {
    import std.stdio;
    auto ls = local["ls"]["-la"];
    writeln(ls());
}







