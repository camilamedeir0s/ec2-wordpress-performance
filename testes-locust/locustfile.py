from locust import HttpUser, TaskSet, task, between

class UserBehavior(TaskSet):
    
    @task(1)
    def index(self):
        self.client.get("/")
        
    @task(2)
    def page_5(self):
        self.client.get("/?p=5")
        
    @task(3)
    def page_1(self):
        self.client.get("/?p=1")

class WebsiteUser(HttpUser):
    tasks = [UserBehavior]
    wait_time = between(1, 5)  # intervalo de espera entre as requisições
