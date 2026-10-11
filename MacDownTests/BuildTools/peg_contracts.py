"""Build instrumented PEG sources in isolation; bound every subprocess."""
from pathlib import Path
import os
import signal
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'Dependency/peg-markdown-highlight'

def run(*args, cwd, input=None, timeout=30):
    process = subprocess.Popen(args, cwd=cwd, stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, start_new_session=True,
                               env=dict(os.environ, UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1'))
    try:
        stdout, stderr = process.communicate(input=input, timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
        raise RuntimeError(f'Timeout in {args}:\n{stdout}\n{stderr}')
    if process.returncode:
        raise RuntimeError(f'Exit {process.returncode} in {args}:\n{stdout}\n{stderr}')
    return subprocess.CompletedProcess(args, process.returncode, stdout, stderr)

with tempfile.TemporaryDirectory(prefix='macdown-peg-') as directory:
    repo = Path(directory)
    shutil.copytree(SOURCE, repo / 'peg',
                    ignore=shutil.ignore_patterns('*.o', '*.dSYM', 'greg', 'pmh_parser.c',
                                                 'pmh_parser_core.c'))
    # The generator directory is deliberately copied explicitly (its name is
    # also the generated executable name in the ignore pattern above).
    shutil.copytree(SOURCE / 'greg', repo / 'peg/greg',
                    ignore=shutil.ignore_patterns('*.o', 'greg'))
    peg = repo / 'peg'
    sanitizers = os.environ.get('PEG_SANITIZERS', 'undefined')
    flags = ['-g', '-O1', '-fsanitize=' + sanitizers, '-fno-omit-frame-pointer']
    run('make', 'CC=clang', 'OFLAGS=-O1', 'XFLAGS=-fsanitize=' + sanitizers, cwd=peg, timeout=120)
    print('Instrumented generator and Markdown parser generated', flush=True)
    binary = repo / 'contracts'
    run('clang', *flags, '-I', str(peg), str(ROOT / 'MacDownTests/BuildTools/peg_contracts.c'),
        str(peg / 'pmh_parser.c'), str(peg / 'pmh_styleparser.c'), '-o', str(binary), cwd=repo)
    print(run(str(binary), cwd=repo).stdout.strip())
    generator = peg / 'greg/greg'
    for length in [1023, 1024, 1025, 2048]:
        name = 'r' * length
        grammar = repo / 'long.leg'
        grammar.write_text(f"start = {name}\n{name} = 'a' {{ $$ = 1; }}\n")
        output = run(str(generator), str(grammar), cwd=repo).stdout
        assert '_1_' + name in output
    grammar = repo / 'deep.leg'
    grammar.write_text("start = " + "('a' " * 1100 + "'b'" + ')' * 1100 + '\n')
    run(str(generator), str(grammar), cwd=repo)
    grammar = repo / 'variables.leg'
    grammar.write_text("start = " + ' '.join(f'x{i}:letter' for i in range(200)) +
                       " { $$ = x0 + x199; }\nletter = 'a' { $$ = 1; }\n%%\n" +
                       'int main(void) { GREG *g = yyparse_new(NULL); '
                       'int ok = yyparse(g); int result = g->ss; yyparse_free(g); '
                       'return !(ok && result == 2); }\n')
    parser = repo / 'variables.c'
    run(str(generator), '-o', str(parser), str(grammar), cwd=repo)
    run('clang', *flags, str(parser), '-o', str(repo / 'variables'), cwd=repo)
    run(str(repo / 'variables'), cwd=repo, input='a' * 200)
    print(f'PASS {sanitizers} generator identifiers, 1100 AST depth and generated 200-variable parser consumed')
