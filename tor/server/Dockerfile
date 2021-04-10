FROM node:lts-alpine3.10
USER root
EXPOSE 12345
WORKDIR /app
COPY . .
RUN npm install -g @edfus/file-server
ENTRYPOINT [ "./run.sh" ]
