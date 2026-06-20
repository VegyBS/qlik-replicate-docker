import json
import click
from .client import ReplicateClient
from .logstream import resume_all_with_logstream


def output(data, as_json):
    if as_json:
        click.echo(json.dumps(data, indent=2))
    else:
        if isinstance(data, (dict, list)):
            click.echo(json.dumps(data, indent=2))
        else:
            click.echo(data)


@click.group()
@click.option("--url", required=True, help="Replicate API base URL")
@click.option("--user", required=True, help="Replicate username")
@click.option("--password", required=True, help="Replicate password")
@click.option("--json", "json_output", is_flag=True, help="Output results in JSON format")
@click.pass_context
def cli(ctx, url, user, password, json_output):
    ctx.obj = {
        "client": ReplicateClient(url, user, password),
        "json": json_output
    }


@cli.command()
@click.pass_context
def status(ctx):
    client = ctx.obj["client"]
    as_json = ctx.obj["json"]

    tasks = client.list_tasks()
    results = {}

    for t in tasks:
        name = t["taskName"]
        status = client.get_task_status(name)
        results[name] = status["status"]

    output(results, as_json)


@cli.command("import-task")
@click.argument("file")
@click.pass_context
def import_task(ctx, file):
    client = ctx.obj["client"]
    as_json = ctx.obj["json"]

    with open(file) as f:
        task_json = json.load(f)

    client.import_task(task_json)
    output({"imported": file}, as_json)


@cli.command("list-tables")
@click.argument("task")
@click.pass_context
def list_tables(ctx, task):
    client = ctx.obj["client"]
    as_json = ctx.obj["json"]

    tables = client.list_task_tables(task)
    output({task: tables}, as_json)


@cli.command()
@click.argument("task")
@click.pass_context
def stop(ctx, task):
    client = ctx.obj["client"]
    as_json = ctx.obj["json"]

    client.stop_task(task)
    output({"stopped": task}, as_json)


@cli.command("stop-all")
@click.pass_context
def stop_all(ctx):
    client = ctx.obj["client"]
    as_json = ctx.obj["json"]

    tasks = client.list_tasks()
    stopped = []

    for t in tasks:
        name = t["taskName"]
        client.stop_task(name)
        stopped.append(name)

    output({"stopped": stopped}, as_json)


@cli.command()
@click.argument("task")
@click.pass_context
def resume(ctx, task):
    client = ctx.obj["client"]
    as_json = ctx.obj["json"]

    client.start_task(task)
    output({"started": task}, as_json)


@cli.command("resume-all")
@click.option("--latency-threshold", default=5.0, help="Max allowed latency before starting children")
@click.pass_context
def resume_all(ctx, latency_threshold):
    client = ctx.obj["client"]
    as_json = ctx.obj["json"]

    result = resume_all_with_logstream(client, latency_threshold)
    output(result, as_json)

