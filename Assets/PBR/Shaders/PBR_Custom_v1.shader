Shader "PBR/Custom_v1"
{
    Properties
	{
		_Color ("Color", Color) = (1.0, 1.0, 1.0, 1.0)
		[NoScaleOffSet]_AlbedoTex ("Albedo", 2D) = "white" {}
        [NoScaleOffSet]_NormalTex ("Normal", 2D) = "bump" {}
        [NoScaleOffSet]_MRAOTex ("MRAO", 2D) = "white" {}
        [NoScaleOffSet]_CubeIndirect ("Cube Indirect", Cube) = "_Skybox" {}
        [NoScaleOffSet]_CubeIrradiance ("Cube Irradiance", Cube) = "_Skybox" {}

    }
    SubShader
	{
        Tags
		{
            "RenderType" = "Opaque"
        }
		
        Pass 
		{
            Name "FORWARD"
            Tags
			{
                "LightMode"="ForwardBase"
            }
             
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #pragma target 3.0
			
            uniform sampler2D _AlbedoTex;
            uniform sampler2D _NormalTex;
			uniform sampler2D _MRAOTex;
            uniform samplerCUBE _CubeIndirect;
            uniform samplerCUBE _CubeIrradiance;
			uniform fixed4 _Color;
			uniform fixed4 _LightColor0;
			
            struct VertexInput
			{
                half4 vertex : POSITION;
                fixed3 normal : NORMAL;
                half4 tangent : TANGENT;
                half2 uv : TEXCOORD0;
            };
			
            struct VertexOutput
			{
                half4 pos : SV_POSITION;
                half2 uv : TEXCOORD0;
                half3 posWorld : TEXCOORD1;
                half3 normalDir : TEXCOORD2;
                half3 tangentDir : TEXCOORD3;
                half3 bitangentDir : TEXCOORD4;
            };
			
			inline half4 Pow5 (half4 x)
			{
				return x * x * x * x * x;
			}
			
			inline half3 FresnelLerp (half3 F0, half3 F90, half cosA)
			{
				half t = Pow5 (1 - cosA);
				return lerp (F0, F90, t);
			}
			
			inline half3 FresnelTerm (half3 F0, half cosA)
			{
				half t = Pow5 (1 - cosA);
				return F0 + (1-F0) * t;
			}
			
			inline half GGXTerm (half NdotH, half roughness)
			{
				half a2 = roughness * roughness;
				half d = (NdotH * a2 - NdotH) * NdotH + 1.0;
				return UNITY_INV_PI * a2 / (d * d + 0.0000001);
			}
			
			inline half SmithJointGGXVisibilityTerm (half NdotL, half NdotV, half roughness)
			{
				half a = roughness;
				half lambdaV = NdotL * (NdotV * (1 - a) + a);
				half lambdaL = NdotV * (NdotL * (1 - a) + a);
				return 0.5f / (lambdaV + lambdaL + 0.0001);
			}
			
			inline half OneMinusReflectivityFromMetallic(half metallic)
			{
				half oneMinusDielectricSpec = unity_ColorSpaceDielectricSpec.a;
				return oneMinusDielectricSpec - metallic * oneMinusDielectricSpec;
			}
			
			inline half3 DiffuseAndSpecularFromMetallic (half3 albedo, half metallic, out half3 specColor, out half oneMinusReflectivity)
			{
				specColor = lerp (unity_ColorSpaceDielectricSpec.rgb, albedo, metallic);
				oneMinusReflectivity = OneMinusReflectivityFromMetallic(metallic);
				return albedo * oneMinusReflectivity;
			}
			
            VertexOutput vert (VertexInput v) 
			{
                VertexOutput o;
                o.uv = v.uv;
                o.normalDir = UnityObjectToWorldNormal(v.normal);
                o.tangentDir = normalize(mul(unity_ObjectToWorld, half4(v.tangent.xyz, 0.0 )).xyz);
                o.bitangentDir = normalize(cross(o.normalDir, o.tangentDir) * v.tangent.w);
                o.posWorld = mul(unity_ObjectToWorld, half4(v.vertex.xyz, 1.0)).xyz;
                o.pos = mul(UNITY_MATRIX_VP, half4(o.posWorld, 1.0));
                return o;
            }
			
            fixed4 frag(VertexOutput i) : COLOR 
			{
                half3x3 tangentTransform = half3x3( i.tangentDir, i.bitangentDir, i.normalDir);
                half3 viewDirection = normalize(_WorldSpaceCameraPos.xyz - i.posWorld.xyz);

                half3 normalLocal = tex2D(_NormalTex, i.uv).xyz * 2.0 - 1.0;
                half3 normalDirection = normalize(mul( normalLocal, tangentTransform ));
                half3 viewReflectDirection = reflect( -viewDirection, normalDirection );
				
                half3 lightDirection = normalize(_WorldSpaceLightPos0.xyz);
                half3 halfDirection = normalize(viewDirection + lightDirection);

                half3 mrao = tex2D(_MRAOTex,i.uv).rgb;
                half gloss = 1.0 - mrao.g;
                half perceptualRoughness = mrao.g;
                half roughness = perceptualRoughness * perceptualRoughness;

                half NdotL = saturate(dot( normalDirection, lightDirection ));
                half LdotH = saturate(dot(lightDirection, halfDirection));
                half3 specularColor = mrao.r;
                half specularMonochrome;
                fixed3 albedoColor = tex2D(_AlbedoTex,i.uv).rgb;
                half3 diffuseColor = albedoColor.rgb * _Color.rgb;
                diffuseColor = DiffuseAndSpecularFromMetallic( diffuseColor, specularColor, specularColor, specularMonochrome );
                specularMonochrome = 1.0 - specularMonochrome;
                half NdotV = saturate(dot( normalDirection, viewDirection ));
                half NdotH = saturate(dot( normalDirection, halfDirection ));
                half VdotH = saturate(dot( viewDirection, halfDirection ));
                half visTerm = SmithJointGGXVisibilityTerm( NdotL, NdotV, roughness );
                half normTerm = GGXTerm(NdotH, roughness);
				
                half specularPBL = (visTerm * normTerm) * UNITY_PI;
				specularPBL = sqrt(max(0.00001, specularPBL)) * NdotL;
							
                half surfaceReduction;
				surfaceReduction = 1.0 - 0.28 * roughness*perceptualRoughness;

                half3 directSpecular = _LightColor0.xyz * specularPBL * FresnelTerm(specularColor, LdotH);
                half grazingTerm = saturate( gloss + specularMonochrome );
                
                half3 indirectSpecular = texCUBElod(_CubeIndirect, half4(viewReflectDirection, mrao.g * 7.0 )).rgb;
                indirectSpecular *= FresnelLerp (specularColor, grazingTerm, NdotV);
                indirectSpecular *= surfaceReduction;
				
                half3 specular = (directSpecular + indirectSpecular);

                half fd90 = 0.5 + 2 * LdotH * LdotH * perceptualRoughness;
                half nlPow5 = Pow5(1.0 - NdotL);
                half nvPow5 = Pow5(1.0 - NdotV);
                half3 directDiffuse = (1.0 +(fd90 - 1.0) * nlPow5) * (1.0 + (fd90 - 1.0) * nvPow5) * NdotL * _LightColor0.xyz;
				half3 irradiance = texCUBE(_CubeIrradiance, viewReflectDirection);
                half3 diffuse = (directDiffuse + irradiance * mrao.b) * diffuseColor;

                fixed4 finalRGBA = fixed4(diffuse + specular, 1.0);
                return finalRGBA;
            }
            ENDCG
        }
    }
    FallBack "Diffuse"
}