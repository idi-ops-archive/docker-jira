## Jira Dockerfile


This repository is used to build [Atlassian Jira](https://www.atlassian.com/software/jira/) Docker image.


### Environment Variables

* CONTEXT_PATH - Used to define http://jira.domain.org/`CONTEXT_PATH`/
* DATABASE_URL - Must be similar to: `postgresql://jira_user:jira_pw@172.17.0.1/jiradb` , also accepts `mysql` instead `postgresql`

### Port(s) Exposed

* `8080 TCP`


### Base Docker Image

* [inclusivedesign/java:openjdk-7](https://github.com/idi-ops/docker-java/)


### Volumes

* /opt/atlassian-home

### Download

    docker pull inclusivedesign/jira


#### Run `Jira`


```
docker run \
-d \
-p 8080:8080 \
--name="jira" \
-e "DATABASE_URL=postgresql://jira_user:jira_pw@172.17.0.1/jiradb" \
-v $PWD/data/jira-home:/opt/atlassian-home/ \
inclusivedesign/jira
```

### Build your own image


    docker build --rm=true -t <your name>/jira .
