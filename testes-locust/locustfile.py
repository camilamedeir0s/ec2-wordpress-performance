from locust import HttpUser, TaskSet, task, between

class UserBehavior(TaskSet):
    
    @task(1)
    def index(self):
        self.client.get("/")
        
    @task(2)
    def page_136(self):
        self.client.get("/?p=136")
        
    @task(3)
    def page_152(self):
        self.client.get("/?p=152")

    @task(3)
    def page_151(self):
        self.client.get("/?p=151")

    @task(4)
    def page_132(self):
        self.client.get("/?p=132")

    @task(5)
    def page_128(self):
        self.client.get("/?p=128")

class WebsiteUser(HttpUser):
    tasks = [UserBehavior]
