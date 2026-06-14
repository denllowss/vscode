FROM codercom/code-server:latest
USER root
EXPOSE 19132/udp
CMD ["code-server", "--bind-addr", "0.0.0.0:6080", "--auth", "none", "/root"]
