FROM inclusivedesign/java:openjdk-7

ENV JIRA_VERSION 6.3.13

RUN yum -y install tar xmlstarlet && \
    yum clean all && \
    /usr/sbin/groupadd atlassian && \
	mkdir -p /opt/atlassian-home && \
    /usr/sbin/useradd --create-home --home-dir /opt/jira --groups atlassian --shell /bin/bash jira && \
    curl -Lks http://www.atlassian.com/software/jira/downloads/binary/atlassian-jira-${JIRA_VERSION}.tar.gz -o /root/jira.tar.gz && \
    tar zxf /root/jira.tar.gz --strip=1 -C /opt/jira && \
    chown -R jira:jira /opt/atlassian-home && \
    chown -R jira:jira /opt/jira && \
    echo "jira.home = /opt/atlassian-home" > /opt/jira/atlassian-jira/WEB-INF/classes/jira-application.properties && \
    mv /opt/jira/conf/server.xml /opt/jira/conf/server-backup.xml

ADD start.sh /usr/local/bin/start.sh

RUN chmod +x /usr/local/bin/start.sh

VOLUME ["/opt/atlassian-home"]

EXPOSE 8080

CMD ["/usr/local/bin/start.sh"]
