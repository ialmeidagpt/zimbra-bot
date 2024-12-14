FROM node:alpine

ENV TZ="America/Recife"

WORKDIR /usr/app

COPY package*.json ./

RUN npm install

COPY . .

CMD ["npm", "start"]
