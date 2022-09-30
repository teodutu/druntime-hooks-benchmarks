from os import chdir, environ
from subprocess import Popen
from sys import argv
from time import time

CMD = 'dub build'
env = environ
env['PATH'] = '/usr/local/google/home/teodutu/work/dlang/dmd-2.097.0/linux/bin64:' + env['PATH']

if len(argv) != 2 and len(argv) != 3:
    print(f'Usage: python3 {argv[0]} <directory> [version]')
    exit(1)

if len(argv) == 3 and argv[2] == 'master':
    CMD += ' --compiler ~/work/dlang/dmd/generated/linux/release/64/dmd'

chdir(argv[1])
min = 10000

for _ in range(100):
    Popen('dub clean', env=env)
    ts1 = time()
    Popen(CMD, env=env).communicate()
    delta_t = time() - ts1
    if delta_t < min:
        min = delta_t

print(delta_t)
