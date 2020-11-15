// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

Shader "Custom/POM"
{
    Properties {
        // normal map texture on the material,
        // default to dummy "flat surface" normalmap
        [KeywordEnum(PLAIN, NORMAL, BUMP, POM, POM_SHADOWS)] MODE("Overlay mode", Float) = 0
        
        _NormalMap("Normal Map", 2D) = "bump" {}
        _MainTex("Texture", 2D) = "grey" {}
        _HeightMap("Height Map", 2D) = "white" {}
        _MaxHeight("Max Height", Range(0.0001, 0.02)) = 0.01
        _StepLength("Step Length", Float) = 0.000001
        _MaxStepCount("Max Step Count", Int) = 64
        
        _Reflectivity("Reflectivity", Range(1, 100)) = 0.5
    }
    
    CGINCLUDE
    #include "UnityCG.cginc"
    #include "UnityLightingCommon.cginc"
    
    inline float LinearEyeDepthToOutDepth(float z)
    {
        return (1 - _ZBufferParams.w * z) / (_ZBufferParams.z * z);
    }

    struct v2f {
        float3 worldPos : TEXCOORD0;
        half3 worldSurfaceNormal : TEXCOORD4;
        // texture coordinate for the normal map
        float2 uv : TEXCOORD5;
        float4 clip : SV_POSITION;
        float3 tangent : TEXCOORD6;
        float3 bitangent : TEXCOORD7;
    };

    // Vertex shader now also gets a per-vertex tangent vector.
    // In Unity tangents are 4D vectors, with the .w component used to indicate direction of the bitangent vector.
    v2f vert (float4 vertex : POSITION, float3 normal : NORMAL, float4 tangent : TANGENT, float2 uv : TEXCOORD0)
    {
        v2f o;
        o.clip = UnityObjectToClipPos(vertex);
        o.worldPos = mul(unity_ObjectToWorld, vertex).xyz;
        half3 wNormal = UnityObjectToWorldNormal(normal);
        half3 wTangent = UnityObjectToWorldDir(tangent.xyz);
        
        o.uv = uv;
        
        o.worldSurfaceNormal = normalize(wNormal);
        o.tangent = normalize(wTangent);
        o.bitangent = normalize(cross(o.worldSurfaceNormal, o.tangent) * tangent.w * unity_WorldTransformParams.w);
        
        return o;
    }

    // normal map texture from shader properties
    sampler2D _NormalMap;
    sampler2D _MainTex;
    sampler2D _HeightMap;
    
    // The maximum depth in which the ray can go.
    uniform float _MaxHeight;
    // Step size
    uniform float _StepLength;
    // Count of steps
    uniform int _MaxStepCount;
    
    float _Reflectivity;

    void frag (in v2f i, out half4 outColor : COLOR, out float outDepth : DEPTH)
    {
        float2 uv = i.uv;
        half3 normal = i.worldSurfaceNormal;               
        float3 worldViewDir = normalize(i.worldPos.xyz - _WorldSpaceCameraPos.xyz);
        
        float3x3 tbn = float3x3(i.tangent, i.bitangent, i.worldSurfaceNormal);
        tbn = transpose(tbn);
        
        float3 tangentViewDir = normalize(mul(tbn, worldViewDir));
        float3 tangentNormal = normalize(mul(tbn, normal));
        
#if MODE_BUMP
        float angle = acos(-dot(tangentNormal, tangentViewDir));
        float h = _MaxHeight - tex2D(_HeightMap, uv).r * _MaxHeight;
        float deltaDir = h * tan(angle);
        uv += deltaDir * tangentViewDir.xz;
#endif   
        float depth = 0;
#if MODE_POM | MODE_POM_SHADOWS    
        float angle = acos(-dot(tangentNormal, tangentViewDir));
        for (int j = 0; j < _MaxStepCount; j++)
        {
            depth = _MaxHeight - tex2D(_HeightMap, uv).r * _MaxHeight;
            float currentDepth = (j + 1) * _StepLength / tan(angle);
            if (currentDepth < depth)
            {
                uv += _StepLength * tangentViewDir.xz; 
            }                 
        }
        
        depth = _MaxHeight - tex2D(_HeightMap, uv).r * _MaxHeight;
#endif

        float3 worldLightDir = normalize(_WorldSpaceLightPos0.xyz);
        float shadow = 0;
#if MODE_POM_SHADOWS
        float3 tangentLightDir = normalize(mul(tbn, worldLightDir));
        angle = acos(dot(tangentNormal, tangentLightDir));
        float2 currentUV = uv;
        float rayDepth = _MaxHeight - tex2D(_HeightMap, currentUV).r * _MaxHeight;
        
        for (int j = 1; j <= _MaxStepCount; j++)
        {
            float currentDepth = rayDepth - j * _StepLength / tan(angle);
            currentUV += _StepLength * tangentLightDir.xz;           
            float surfaceDepth = _MaxHeight - tex2D(_HeightMap, currentUV).r * _MaxHeight;
            
            if (currentDepth > surfaceDepth)
            {
                shadow += max(1.0, (currentDepth - surfaceDepth) / surfaceDepth);
            }       
        }
#endif
                
#if !MODE_PLAIN
        normal = UnpackNormal(tex2D(_NormalMap, uv));
        normal = mul(tbn, normal);
#endif

        // Diffuse lightning
        half cosTheta = max(0, dot(normal, worldLightDir));
        half3 diffuseLight = max(0, cosTheta) * _LightColor0 * max(0, 1 - shadow);
        
        // Specular lighting (ad-hoc)
        half specularLight = pow(max(0, dot(worldViewDir, reflect(worldLightDir, normal))), _Reflectivity) * _LightColor0 * max(0, 1 - shadow); 

        // Ambient lighting
        half3 ambient = ShadeSH9(half4(UnityObjectToWorldNormal(normal), 1));

        // Return resulting color
        float3 texColor = tex2D(_MainTex, uv);
        outColor = half4((diffuseLight + specularLight + ambient) * texColor, 0);
        outDepth = LinearEyeDepthToOutDepth(LinearEyeDepth(i.clip.z - depth));
    }
    ENDCG
    
    SubShader
    {    
        Pass
        {
            Name "MAIN"
            Tags { "LightMode" = "ForwardBase" }
        
            ZTest Less
            ZWrite On
            Cull Back
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile_local MODE_PLAIN MODE_NORMAL MODE_BUMP MODE_POM MODE_POM_SHADOWS
            ENDCG
            
        }
    }
}