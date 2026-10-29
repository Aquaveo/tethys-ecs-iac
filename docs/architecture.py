"""Render docs/architecture.png from the resources in tofu/.

    uvx --with diagrams python docs/architecture.py   # needs Graphviz (`dot`) on PATH
"""

from pathlib import Path

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import Fargate
from diagrams.aws.database import RDS
from diagrams.aws.general import Users
from diagrams.aws.management import Cloudwatch, SystemsManagerParameterStore
from diagrams.aws.network import CloudFront, ElbApplicationLoadBalancer
from diagrams.aws.storage import S3
from diagrams.onprem.ci import GithubActions

OUT = Path(__file__).with_suffix("")

graph_attr = {"pad": "0.4", "nodesep": "0.7", "ranksep": "1.1", "splines": "spline",
              "fontsize": "14", "labelloc": "t"}
edge_attr = {"fontsize": "11"}

with Diagram("tethys-ecs-iac: one Tethys portal on ECS Fargate", filename=str(OUT), show=False,
             direction="LR", graph_attr=graph_attr, edge_attr=edge_attr, outformat="png"):
    users = Users("Users")
    ci = GithubActions("Portal repo CI\n(OIDC)")

    with Cluster("AWS account, one OpenTofu state key per portal"):
        cdn = CloudFront("CloudFront\nportal_domain + aliases")
        ssm = SystemsManagerParameterStore("SSM SecureStrings\n/<org>/<app>/*")

        with Cluster("VPC (vpc_id)"):
            alb = ElbApplicationLoadBalancer("ALB\n:80 / :443")
            with Cluster("ECS cluster"):
                web = Fargate("web service\nuvicorn | gunicorn")
                provision = Fargate("provision task\none-shot per deploy")

        bucket = S3("S3\n/static /media\ngeoglows cache")
        logs = Cloudwatch("CloudWatch Logs")

    db = RDS("Postgres pooler\n(external)")

    users >> Edge(label="HTTPS") >> cdn
    cdn >> Edge(label="default, no cache") >> alb >> web
    cdn >> Edge(label="/static/* /media/* (OAC)", style="dashed") >> bucket
    ci >> Edge(label="sync-secrets", style="dotted", color="firebrick") >> ssm
    ci >> Edge(label="tofu apply + run-task", style="dotted", color="navy") >> provision
    ssm >> Edge(label="secrets at task start", style="dotted", color="firebrick") >> [provision, web]
    [provision, web] >> db
    [provision, web] >> Edge(style="dashed") >> bucket
    [provision, web] >> Edge(color="gray") >> logs
