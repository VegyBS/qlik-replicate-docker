import time

def find_logstream_parents(client):
    parents = {}
    tasks = client.list_tasks()

    for t in tasks:
        name = t["taskName"]
        task_def = client.export_task(name)
        target = task_def.get("targetEndpoint", {})

        if target.get("type") == "LogStream":
            parents[name] = target.get("name")

    return parents


def find_logstream_children(client, parents):
    children = {p: [] for p in parents}
    tasks = client.list_tasks()

    for t in tasks:
        name = t["taskName"]
        task_def = client.export_task(name)
        source = task_def.get("sourceEndpoint", {})
        source_name = source.get("name")

        for parent_task, parent_endpoint in parents.items():
            if source_name == parent_endpoint:
                children[parent_task].append(name)

    return children


def wait_for_parents_ready(client, parents, latency_threshold, poll_interval=10, max_wait_seconds=1800):
    start = time.time()
    parent_names = list(parents.keys())

    while True:
        all_ready = True

        for name in parent_names:
            status = client.get_task_status(name)
            state = status["status"]
            latency = client.get_latency(name)

            print(f"[logstream] {name}: state={state}, latency={latency}")

            if state != "Running":
                all_ready = False
            elif latency is None or latency > latency_threshold:
                all_ready = False

        if all_ready:
            print("[logstream] All parents ready")
            return True

        if time.time() - start > max_wait_seconds:
            print("[logstream] Timeout waiting for parents")
            return False

        print(f"[logstream] Waiting {poll_interval}s...")
        time.sleep(poll_interval)


def resume_all_with_logstream(client, latency_threshold):
    parents = find_logstream_parents(client)
    children = find_logstream_children(client, parents)

    all_tasks = client.list_tasks()
    all_names = {t["taskName"] for t in all_tasks}
    parent_names = set(parents.keys())
    child_names = {c for lst in children.values() for c in lst}
    other_names = list(all_names - parent_names - child_names)

    actions = {
        "parents_started": [],
        "children_started": [],
        "others_started": [],
        "parents_waited_for": list(parent_names)
    }

    # 1. Start parents
    for name in parent_names:
        status = client.get_task_status(name)
        if status["status"] != "Running":
            client.start_task(name)
            actions["parents_started"].append(name)

    # 2. Wait for parents
    wait_for_parents_ready(client, parents, latency_threshold)

    # 3. Start children
    for parent, childs in children.items():
        for name in childs:
            status = client.get_task_status(name)
            if status["status"] != "Running":
                client.start_task(name)
                actions["children_started"].append(name)

    # 4. Start others
    for name in other_names:
        status = client.get_task_status(name)
        if status["status"] != "Running":
            client.start_task(name)
            actions["others_started"].append(name)

    return actions

