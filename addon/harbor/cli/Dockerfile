FROM photon:1.0

MAINTAINER weike weike.cs@gmail.com

RUN set -ex \
    && tdnf distro-sync -y \
    && tdnf install python-pip -y \
    && pip install \
           --no-cache-dir \
           --index-url=https://pypi.tuna.tsinghua.edu.cn/simple \
           python-harborclient

CMD ["harbor"]
