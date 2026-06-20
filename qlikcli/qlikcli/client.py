import requests

class ReplicateClient:
    def __init__(self, base_url, username, password, timeout=10):
        self.base_url = base_url.rstrip("/")
        self.auth = (username, password)
        self.timeout = timeout

    def _get(self, path):
        r = requests.get(f"{self.base_url}{path}", auth=self.auth, timeout=self.timeout)
        r.raise_for_status()
        return r.json()

    def _post(self, path, json=None):
        r = requests.post(f"{self.base_url}{path}", json=json, auth=self.auth, timeout=self.timeout)
        r.raise_for_status()
        return r.json() if r.content else None

    # --- tasks ---
    def list_tasks(self):
        return self._get("/tasks")

    def get_task_status(self, task_name):
        return self._get(f"/tasks/{task_name}/status")

    def start_task(self, task_name):
        return self._post(f"/tasks/{task_name}/start")

    def stop_task(self, task_name):
        return self._post(f"/tasks/{task_name}/stop")

    def export_task(self, task_name):
        return self._get(f"/tasks/{task_name}/export")

    def import_task(self, task_json):
        return self._post("/tasks/import", json=task_json)

    def get_latency(self, task_name):
        status = self.get_task_status(task_name)
        return status.get("cdc", {}).get("latency")

    def list_task_tables(self, task_name):
        task_def = self.export_task(task_name)
        return [
            f"{t.get('schemaName')}.{t.get('tableName')}"
            for t in task_def.get("tables", [])
        ]
