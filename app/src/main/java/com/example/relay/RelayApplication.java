package com.example.relay;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.http.HttpMethod;
import org.springframework.integration.dsl.IntegrationFlow;
import org.springframework.integration.http.dsl.Http;

/**
 * 検証用の最小中継AP。
 * POST /relay で受けた電文を変換し、環境名を付けて返す。
 * （実際の検証では、EIP学習で作っている中継APに差し替えてOK）
 */
@SpringBootApplication
public class RelayApplication {

    public static void main(String[] args) {
        SpringApplication.run(RelayApplication.class, args);
    }

    @Bean
    IntegrationFlow relayFlow(@Value("${relay.env-name}") String envName) {
        return IntegrationFlow
                .from(Http.inboundGateway("/relay")
                        .requestMapping(m -> m.methods(HttpMethod.POST))
                        .requestPayloadType(String.class))
                .<String, String>transform(s -> "[" + envName + "] " + s.toUpperCase())
                .get();
    }
}
