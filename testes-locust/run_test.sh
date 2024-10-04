#!/bin/sh

# Definindo as variáveis
users=50
spawn_rate=10
host="http://localhost:8080"
run_time="3m20s"

# Executando o comando com as variáveis
locust -f locustfile.py --headless -u $users -r $spawn_rate --run-time $run_time --host $host
