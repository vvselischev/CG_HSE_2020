Shader "0_Custom/Cubemap"
{
    Properties
    {
        _BaseColor ("Color", Color) = (0, 0, 0, 1)
        _Roughness ("Roughness", Range(0.03, 1)) = 1
        _Cube ("Cubemap", CUBE) = "" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"
            
            #define EPS 1e-7

            struct appdata
            {
                float4 vertex : POSITION;
                fixed3 normal : NORMAL;
            };

            struct v2f
            {
                float4 clip : SV_POSITION;
                float4 pos : TEXCOORD1;
                fixed3 normal : NORMAL;
            };

            float4 _BaseColor;
            float _Roughness;
            
            samplerCUBE _Cube;
            half4 _Cube_HDR;
            
            v2f vert (appdata v)
            {
                v2f o;
                o.clip = UnityObjectToClipPos(v.vertex);
                o.pos = mul(UNITY_MATRIX_M, v.vertex);
                o.normal = UnityObjectToWorldNormal(v.normal);
                return o;
            }

            uint Hash(uint s)
            {
                s ^= 2747636419u;
                s *= 2654435769u;
                s ^= s >> 16;
                s *= 2654435769u;
                s ^= s >> 16;
                s *= 2654435769u;
                return s;
            }
            
            float Random(uint seed)
            {
                return float(Hash(seed)) / 4294967295.0; // 2^32-1
            }
            
            float3 SampleColor(float3 direction)
            {   
                half4 tex = texCUBE(_Cube, direction);
                return DecodeHDR(tex, _Cube_HDR).rgb;
            }
            
            float Sqr(float x)
            {
                return x * x;
            }
            
            // Calculated according to NDF of Cook-Torrance
            float GetSpecularBRDF(float3 viewDir, float3 lightDir, float3 normalDir)
            {
                float3 halfwayVector = normalize(viewDir + lightDir);               
                
                float a = Sqr(_Roughness);
                float a2 = Sqr(a);
                float NDotH2 = Sqr(dot(normalDir, halfwayVector));
                
                return a2 / (UNITY_PI * Sqr(NDotH2 * (a2 - 1) + 1));
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float3 normal = normalize(i.normal);
                
                float3 viewDirection = normalize(_WorldSpaceCameraPos - i.pos.xyz);
                
                // Replace this specular calculation by Montecarlo.
                // Normalize the BRDF in such a way, that integral over a hemysphere of (BRDF * dot(normal, w')) == 1
                // TIP: use Random(i) to get a pseudo-random value.
                float3 viewRefl = reflect(-viewDirection.xyz, normal);
                float3 specular = SampleColor(viewRefl);
                
                float3 result = float3(0, 0, 0);
                float3 resultBRDF = float3(0, 0, 0);
                int N = 10000;

                // Actually, we can fairly calculate the tangent space to rotate w,
                // but it affects the performance too much.
                // So just sample points over all sphere and check if angle(w, normal) <= pi / 2 <=> cos >= 0
//                float3 tmp = float3(1, 0, 0);
//                if (abs(normal.x) > EPS)
//                {
//                    tmp = float3(0, 0, 1);
//                }
//                float3 tangent = normalize(cross(normal, tmp));
//                float3 binormal = normalize(cross(normal, tangent));
//                float3x3 wToNormal = float3x3(tangent, binormal, normal);

                for (int i = 0; i < N; i++)
                {
                    float cosTheta = Random(i) * 2 - 1;
                    float sinTheta = sqrt(1 - Sqr(cosTheta));
                    float alpha = Random(N + i) * 2 * UNITY_PI;
                    float3 w = float3(sinTheta * cos(alpha), sinTheta * sin(alpha), cosTheta);                   

                    float dTheta = dot(normal, normalize(w));

                    // why if (!...) continue; causes unity to crash?..
                    if (dTheta >= 0)
                    {
                        float BRDF = GetSpecularBRDF(viewDirection, w, normal);
                        resultBRDF += BRDF * dTheta;
                        result += SampleColor(w) * BRDF * dTheta;
                    }
                }
                result /= resultBRDF;
                
                return fixed4(result, 1);
            }
            ENDCG
        }
    }
}
