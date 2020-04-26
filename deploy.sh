#!/usr/bin/env bash

# Write by Jiang Yiheng

#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program.  If not, see <https://www.gnu.org/licenses/>.

OPENJDK_VERSION="14.0.1"
ZOOKEEPER_VERSION="3.6.0"
HADOOP_VERSION="3.2.1"
URL_OPENJDK="https://download.java.net/java/GA/jdk14.0.1/664493ef4a6946b186ff29eb326336a2/7/GPL/openjdk-14.0.1_linux-x64_bin.tar.gz"
URL_ZOOKEEPER="https://mirrors.ocf.berkeley.edu/apache/zookeeper/zookeeper-3.6.0/apache-zookeeper-3.6.0-bin.tar.gz"
URL_HADOOP="https://mirrors.ocf.berkeley.edu/apache/hadoop/common/hadoop-3.2.1/hadoop-3.2.1.tar.gz"

HOSTNAME="master"
HADOOP_PASSWORD="lb8Uk#3sjxMc"

banner () {
    echo "Setting up..."
    echo
    cat <<'EOF'
 /$$$$$$$                  /$$     /$$ /$$ /$$                                    
| $$__  $$                |  $$   /$$/|__/| $$                                    
| $$  \ $$ /$$   /$$       \  $$ /$$/  /$$| $$$$$$$   /$$$$$$  /$$$$$$$   /$$$$$$ 
| $$$$$$$ | $$  | $$        \  $$$$/  | $$| $$__  $$ /$$__  $$| $$__  $$ /$$__  $$
| $$__  $$| $$  | $$         \  $$/   | $$| $$  \ $$| $$$$$$$$| $$  \ $$| $$  \ $$
| $$  \ $$| $$  | $$          | $$    | $$| $$  | $$| $$_____/| $$  | $$| $$  | $$
| $$$$$$$/|  $$$$$$$          | $$    | $$| $$  | $$|  $$$$$$$| $$  | $$|  $$$$$$$
|_______/  \____  $$          |__/    |__/|__/  |__/ \_______/|__/  |__/ \____  $$
           /$$  | $$                                                     /$$  \ $$
          |  $$$$$$/                                                    |  $$$$$$/
           \______/                                                      \______/ 
EOF

    echo
}

setup_ssh () {
    
}

install_java () {
    curl -O $URL_OPENJDK
    tar xzf "openjdk-${OPENJDK_VERSION}_linux-x64_bin.tar.gz" -C /opt/
    ln -s /opt/jdk-${OPENJDK_VERSION} /opt/jdk

    cat <<"EOF" >> /etc/profile.d/jdk.sh
export JAVA_HOME=/opt/jdk
export PATH="${PATH}:${JAVA_HOME}/bin"
EOF

    alternatives --install /usr/bin/java java /opt/jdk-${OPENJDK_VERSION}/bin/java 3
    alternatives --install /usr/bin/javac javac /opt/jdk-${OPENJDK_VERSION}/bin/javac 3
}

config_hostname () {
    echo $HOSTNAME > /etc/hostname

    localip=$(ip a | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
    echo "$localip ${HOSTNAME}.hadoop.lan" >> /etc/hosts
}

install_if_not () {
    echo "checking whether $1 is installed"
    rpm -qa | grep -qw $1 || yum install -y $1
}

config_ntp () {
    install_if_not ntp
    install_if_not ntpdate
    systemctl enable ntpd
    systemctl start ntpd
}

initialize () {
    if [ $USER != root ]
    then
        echo "You must run this script as root !"
        exit 127
    fi

    yum check-update
    install_if_not curl

    local WD="/tmp/setup-$(( (RANDOM % 10000) + 1 ))"
    mkdir -p $WD
    cd $WD
    pwd
}

install_zookeeper () {

    curl -O $URL_ZOOKEEPER
    tar xzf apache-zookeeper-${ZOOKEEPER_VERSION}-bin.tar.gz -C /opt
    mv /opt/apache-zookeeper-${ZOOKEEPER_VERSION}-bin /opt/zookeeper-${ZOOKEEPER_VERSION}
    ln -s /opt/zookeeper-${ZOOKEEPER_VERSION} /opt/zookeeper

    groupadd zookeeper
    useradd -g zookeeper -d /opt/zookeeper -s /sbin/nologin zookeeper

    mkdir -p /opt/zookeeper/data
    mkdir -p /opt/zookeeper/logs
    mkdir -p /var/lib/zookeeper

    cat <<'EOF' >> /opt/zookeeper/conf/zoo.cfg
tickTime=2000
initLimit=10
syncLimit=5
dataDir=/opt/zookeeper/data
clientPort=2181
EOF

    cat <<'EOF' > /usr/lib/systemd/system/zookeeper.service
[Unit]
Description=Zookeeper Service
Requires=network.target
After=network.target

[Service]
Type=forking
SyslogIdentifier=zookeeper
User=zookeeper
Group=zookeeper
ExecStart=/opt/zookeeper/bin/zkServer.sh start
ExecStop=/opt/zookeeper/bin/zkServer.sh stop
WorkingDirectory=/var/lib/zookeeper

[Install]
WantedBy=multi-user.target
EOF

    chown -R zookeeper:zookeeper /opt/zookeeper-${ZOOKEEPER_VERSION}
    systemctl daemon-reload
    systemctl enable zookeeper.service
    systemctl start  zookeeper.service
}

install_hadoop () {
    curl -O $URL_HADOOP
    tar xzf hadoop-${HADOOP_VERSION}.tar.gz -C /opt/
    ln -s /opt/hadoop-${HADOOP_VERSION} /opt/hadoop

    groupadd hadoop
    useradd -g hadoop -d /opt/hadoop hadoop

    echo "Setting password for user hadoop"
    cat <<<"hadoop:$HADOOP_PASSWORD" | chpasswd
    
    ssh-keygen -t rsa
    cat $HOME/.ssh/id_rsa.pub > $HOME/.ssh/authorized_keys
    chmod 600 $HOME/.ssh/id_rsa
    chmod 644 $HOME/.ssh/id_rsa.pub
    chmod 644 $HOME/.ssh/authorized_keys

    cat <<'EOF' > /opt/hadoop/.bash_profile
## HADOOP env variables
export HADOOP_HOME=/opt/hadoop
export HADOOP_COMMON_HOME=$HADOOP_HOME
export HADOOP_HDFS_HOME=$HADOOP_HOME
export HADOOP_MAPRED_HOME=$HADOOP_HOME
export HADOOP_YARN_HOME=$HADOOP_HOME
export HADOOP_OPTS="-Djava.library.path=$HADOOP_HOME/lib/native"
export HADOOP_COMMON_LIB_NATIVE_DIR=$HADOOP_HOME/lib/native
export PATH=$PATH:$HADOOP_HOME/sbin:$HADOOP_HOME/bin
EOF
    
    cat /etc/profile.d/jdk.sh >> /opt/hadoop/etc/hadoop/hadoop-env.sh

    sed -i.origin -f - /opt/hadoop/etc/hadoop/core-site.xml <<EOF
/<configuration>/a\\
    <property>\\
        <name>fs.defaultFS</name>\\
        <value>hdfs://${HOSTNAME}.hadoop.lan:9000/</value>\\
    </property>
EOF

    sed -i.origin -f - /opt/hadoop/etc/hadoop/hdfs-site.xml <<"EOF"
/<configuration>/a\
    <property>\
        <name>dfs.data.dir</name>\
        <value>file:///opt/volume/datanode</value>\
      </property>\
      <property>\
        <name>dfs.name.dir</name>\
        <value>file:///opt/volume/namenode</value>\
    </property>
EOF

    sed -i.origin -f - /opt/hadoop/etc/hadoop/mapred-site.xml <<"EOF"
/<configuration>/a\
    <property>\
        <name>mapreduce.framework.name</name>\
        <value>yarn</value>\
    </property>
EOF

    sed -i.origin -f - /opt/hadoop/etc/hadoop/yarn-site.xml <<"EOF"
/<configuration>/a\
    <property>\
        <name>yarn.nodemanager.aux-services</name>\
        <value>mapreduce_shuffle</value>\
    </property>
EOF

    mkdir -p /opt/volume/namenode
    mkdir -p /opt/volume/datanode

    chown -R hadoop:hadoop /opt/volume/
    chown -R hadoop:hadoop /opt/hadoop-${HADOOP_VERSION}

    cat <<"EOF" >> /etc/rc.d/rc.local
su - hadoop -c "/opt/hadoop/sbin/start-dfs.sh"
su - hadoop -c "/opt/hadoop/sbin/start-yarn.sh"
exit 0
EOF

    chmod +x /etc/rc.d/rc.local
    systemctl enable rc-local
    systemctl start rc-local
}

banner
initialize
config_hostname
install_if_not net-tools
install_if_not psmisc
config_ntp
install_java
install_zookeeper
install_hadoop
