FROM mcs07/rdkit:2020.03.2 as rdkit-env

FROM bitnami/postgresql:12 AS rdkit-postgres-build-env

USER root

RUN apt-get update \
 && apt-get install -yq --no-install-recommends \
    ca-certificates \
    build-essential \
    cmake \
    wget \
    libboost-dev \
    libboost-iostreams-dev \
    libboost-python-dev \
    libboost-regex-dev \
    libboost-serialization-dev \
    libboost-system-dev \
    libboost-thread-dev \
    libcairo2-dev \
    libeigen3-dev \
    python3-dev \
    python3-numpy \
    patch \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Copy rdkit installation from rdkit-env
COPY --from=rdkit-env /usr/lib/libRDKit* /opt/bitnami/postgresql/lib/
COPY --from=rdkit-env /usr/lib/cmake/rdkit/* /opt/bitnami/postgresql/lib/cmake/rdkit/
COPY --from=rdkit-env /usr/share/RDKit /opt/bitnami/postgresql/share/RDKit
COPY --from=rdkit-env /usr/include/rdkit /opt/bitnami/postgresql/include/rdkit
COPY --from=rdkit-env /usr/lib/python3/dist-packages/rdkit /opt/bitnami/postgresql/lib/python3/dist-packages/rdkit


ARG RDKIT_VERSION=Release_2020_03_2
RUN wget --quiet https://github.com/rdkit/rdkit/archive/${RDKIT_VERSION}.tar.gz \
 && tar -xzf ${RDKIT_VERSION}.tar.gz \
 && mv rdkit-${RDKIT_VERSION} rdkit \
 && rm ${RDKIT_VERSION}.tar.gz

WORKDIR /rdkit/Code/PgSQL/rdkit

COPY patches/*.patch /tmp/
RUN patch CMakeLists.txt /tmp/cmakelists.txt.patch \
 && patch adapter.cpp /tmp/adapter.cpp.patch

RUN cmake -Wno-dev \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_SYSTEM_PREFIX_PATH=/opt/bitnami/postgresql \
    -D CMAKE_INSTALL_PREFIX=/opt/bitnami/postgresql \
    -D CMAKE_MODULE_PATH=/rdkit/Code/cmake/Modules \
    -D RDK_BUILD_AVALON_SUPPORT=ON \
    -D RDK_BUILD_INCHI_SUPPORT=ON \
    -D RDKit_DIR=/opt/bitnami/postgresql/lib \
    -D PostgreSQL_ROOT=/opt/bitnami/postgresql \
    -D PostgreSQL_TYPE_INCLUDE_DIR=/opt/bitnami/postgresql/include/server/ \
    .

RUN make -j $(nproc)

FROM bitnami/postgresql:12 AS rdkit-postgres-env

USER root

RUN apt-get update \
    && apt-get install -yq vim bash-completion wget \
       gnupg \
    && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
    && echo "deb http://apt.postgresql.org/pub/repos/apt/ buster-pgdg main" | tee  /etc/apt/sources.list.d/pgdg.list

# Install runtime dependencies
RUN apt-get update \
 && apt-get install -yq --no-install-recommends \
    libboost-atomic1.67.0 \
    libboost-chrono1.67.0 \
    libboost-date-time1.67.0 \
    libboost-iostreams1.67.0 \
    libboost-python1.67.0 \
    libboost-regex1.67.0 \
    libboost-serialization1.67.0 \
    libboost-system1.67.0 \
    libboost-thread1.67.0 \
    libcairo2-dev \
    python3-dev \
    python3-numpy \
    python3-cairo \
    zlib1g-dev \
    gcc \
    make \
    git \
    vim \
    postgresql-server-dev-12 \
    postgresql-plpython3-12 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Copy rdkit installation from rdkit-build-env
COPY --from=rdkit-env /usr/lib/libRDKit* /opt/bitnami/postgresql/lib/
COPY --from=rdkit-env /usr/lib/cmake/rdkit /opt/bitnami/postgresql/lib/cmake/rdkit
COPY --from=rdkit-env /usr/share/RDKit /opt/bitnami/postgresql/share/RDKit
COPY --from=rdkit-env /usr/include/rdkit /opt/bitnami/postgresql/include/rdkit
COPY --from=rdkit-env /usr/lib/python3/dist-packages/rdkit /opt/bitnami/postgresql/lib/python3/dist-packages/rdkit

# Copy rdkit postgres extension from rdkit-postgres-build-env
COPY --from=rdkit-postgres-build-env /rdkit/Code/PgSQL/rdkit/rdkit--3.8.sql /opt/bitnami/postgresql/share/extension
COPY --from=rdkit-postgres-build-env /rdkit/Code/PgSQL/rdkit/rdkit.control /opt/bitnami/postgresql/share/extension
COPY --from=rdkit-postgres-build-env /rdkit/Code/PgSQL/rdkit/librdkit.so /opt/bitnami/postgresql/lib/rdkit.so


#Copy plpython3u extension to bitnami directory
RUN cp /usr/share/postgresql/12/extension/plpython3u--1.0.sql /opt/bitnami/postgresql/share/extension/ \
   && cp /usr/share/postgresql/12/extension/plpython3u.control /opt/bitnami/postgresql/share/extension/ \
   && cp /usr/share/postgresql/12/extension/plpython3u--unpackaged--1.0.sql /opt/bitnami/postgresql/share/extension/ \
   && cp /usr/lib/postgresql/12/lib/plpython3.so /opt/bitnami/postgresql/lib/

# pgsql-gzip extension
RUN git clone https://github.com/pramsey/pgsql-gzip/ \
    && cd pgsql-gzip \
    && git checkout ba35a082caa809d1887189dba163c4d173a000cc \
    && make && make install \
    && cd .. && rm -r pgsql-gzip

USER 1001
